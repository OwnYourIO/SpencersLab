# Interview — Ops / security reviewer

Interviewed 2026-10-21 (inline, single session).

## Q1: What is the runner lifecycle, and what happens on failure?

- **Restart = re-attach.** The identity (uuid+token) lives in `/data/.runner`
  [4]; as long as that PVC survives, a pod restart simply re-registers the
  *same* runner record. In-flight jobs are lost on restart; the server
  reclaims them via `ZOMBIE_TASK_TIMEOUT` (10m default) [6].
- **Lost identity** (PVC gone / `.runner` corrupted) = the runner record on
  the server becomes orphaned. Recovery: create a fresh runner (UI/API),
  update the token/uuid the chart consumes (new Bitwarden value →
  ExternalSecret refresh), delete the stale record (UI or
  `DELETE /api/v1/admin/actions/runners/{id}`) [8].
- **Token rotation**: the UI offers per-runner `reset_registration_token`
  (new token, same uuid) [8]; or re-register as a brand-new runner (new
  uuid+token). Either way the secret backing the chart must be updated.
- **Visibility**: admin UI `/admin/actions/runners` shows Name / Labels /
  Owner / online-offline status, with Edit / Delete [5][8]. A dead pod
  shows offline (report_interval 1s — the UI flips when reports stop) [4].
- **Version bumps**: image-tag change only; the `.runner` file stays valid,
  so upgrades re-attach rather than re-register [4][2].

## Q2: What are the replica and blast-radius rules?

- **Never share one uuid+token across pods.** Two daemons with the same
  identity both fetch jobs → double execution / state corruption [4][8].
  replicas>1 requires **per-replica identity**: either a per-pod
  initContainer that self-registers (official forgejo example pattern [4])
  or a StatefulSet with per-ordinal PVCs (gitea example [11]). At dev scale
  the chart should default to **replicas=1** and document that scaling out
  means scaling *runners*, not replicas of one identity.
- **Privilege blast radius**: the DinD container must be `privileged: true`
  (root-equivalent on the node) [10][4]. Mitigations to encode:
  - runner container itself stays **non-privileged** (the official example
    does exactly this; repo standard: drop ALL capabilities,
    allowPrivilegeEscalation false — note the privileged DinD is the one
    sanctioned exception, documented in the chart).
  - `container.privileged: false` (config default) → job containers are not
    privileged [4].
  - `container.docker_host: "-"` (config **default**) → job containers do
    NOT get the docker socket by default [4][23]; the socket mount is for
    the runner daemon, not the jobs. Opt-in per-job docker access is a
    values switch, off by default.
  - The registration token is secret material: Bitwarden → ExternalSecret →
    K8s Secret, mounted read-only, consumed via `token_url: file:` (the
    runner reads it from disk; it never appears on the command line or in
    logs) [4].
- **Secrets surface**: one new Bitwarden item (runner registration token).
  The existing `forgejo-token` item (user access token for Coder workspaces)
  is a different concern — do not conflate them [18].

## Q3: What day-2 operations must the plan anticipate?

1. **Stale-runner hygiene** — the emptyDir/self-register pattern produces
   one orphaned runner per pod recreation; the PVC pattern avoids it by
   design. The plan should still document the delete path (UI button /
   DELETE API) [8].
2. **Docker minimum 25.0** (v13 requirement) and 28.0.1+ recommended for
   IPv6 [3] — the DinD image pin must respect this (both 28.3.0 and 29.9.1
   do).
3. **Node disk pressure** — the docker-data PVC holds job images; 10–20Gi
   on a ~99GiB root is safe, but the plan should note that a runaway
   `docker-data` fills the *node root fs* (local-path), not an isolated
   volume [19][14].
4. **Server-side timeouts** the runner must respect: job 3h (runner
   `timeout`/`shutdown_timeout` mirror the server's `ENDLESS_TASK_TIMEOUT`
   3h) [6][4].
5. **Ephemeral runners** (Forgejo 15+) exist but daemon mode refuses them
   (daemon.go:84) — they are for one-shot `register` invocations, not this
   deployment [4].
