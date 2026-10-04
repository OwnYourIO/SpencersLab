# Plan: Fix external SSO outage — wedged Keycloak MQTT publisher; self-heal via liveness probe

Type: bug. First diagnosed: 2026-09-27. Revised: 2026-10-04 (approach changed from
"swap/patch the MQTT JAR" to "bake recovery into the container health check", per user).
Affects: boards/player/audiobook-player (and every hub service gated by Keycloak
forward-auth or the IP allowlist) from the public internet. Internal (LAN/mesh)
access unaffected.

## Goal

External users can log in through Keycloak again: after an SSO login their current
remote IP lands in `user-allowlist-remote` within seconds. The known failure mode —
the MQTT publisher client dying on every Home Assistant / broker restart and never
recovering — becomes self-healing: a liveness probe detects the dead client and the
kubelet restarts the container, which reliably reconnects. No new workloads, no
CronJob, no JAR swap, no Java build.

## Skills

- `helm-chart-creation` — chart values change in `charts/keycloakx` + lint/template
  validation discipline.
- `kubernetes-skill` — probe semantics (startup gates liveness), StatefulSet rollout
  behavior, restartPolicy expectations.

## MCP Servers

- `readonly-infra-kubernetes` — keycloak pod spec/probes/status before and after.
- `readonly-proxy-local-kubernetes` — hub traefik + `user-allowlist-mqtt` sidecar logs.
- `readonly-global-grafana` — Loki verification (datasource uid `P8E80F9AEF21F6940`).
- No `admin-*` servers: the only cluster mutation is the ArgoCD rollout triggered by
  merging the chart change.

## Verified context (diagnosis, all evidenced)

**Symptom:** internally everything works; externally, anonymous/public paths work
(polls invite links, paste, login realm JSON) but every host requiring Keycloak login
or the remote allowlist bounced 403→307 in an infinite SSO loop.

**Root cause chain (2026-09-27):**
1. External access is gated by `user-allowlist-remote` in the hub traefik; that file
   (`/data/user-allowlist.yaml`) is maintained by the `user-allowlist-mqtt` sidecar
   from Keycloak LOGIN events on MQTT topic `keycloak` (broker = Home Assistant's
   embedded MQTT at `mqtt.spencerslab.com:1883`).
2. Keycloak publishes via the third-party listener JAR
   (`softwarefactory-project/keycloak-event-listener-mqtt`) configured through
   `KC_SPI_EVENTS_LISTENER_MQTT_*` env (`charts/keycloakx/templates/secret-keycloak-admin.yaml`).
3. Loki evidence: user `thehackmeister` logged in externally (jellyfin, IP
   172.59.224.188) — the LOGIN event fired and the publish failed:
   `Publishing failed!: Client is not connected (32104)`. 1801 such failures in 30d,
   starting ≥2026-09-06; 8 "MQTT Ping … Timed out" disconnect episodes; **0
   recoveries**. Result: no new remote IPs allowlisted for ~3 weeks.
4. Corroborated dead ends ruled out: edge TLS/DNS/tunnel fine for working hosts; hub
   plugins/file-provider/`oidc-keycloak` middleware all healthy; Keycloak itself healthy.

**Follow-up findings (2026-09-28), which killed the JAR-swap approach:**
- The PVC already holds upstream **22.0.0** (813864 bytes, downloaded January) —
  which *already* sets `setAutomaticReconnect(true)`. Auto-reconnect is configured
  but empirically never recovers in this environment; nothing configurable changes
  that (no SPI option exists).
- `Connection could not be established` appears **0 times in 30d** → every keycloak
  boot connects cleanly. Restart is a reliable cure; in-place reconnect is not.
- Deployed pod (`infra-keycloakx-0`, `quay.io/keycloak/keycloak:26.7.2`, UBI9-based
  with bash): startupProbe `/health`, liveness `/health/live`, readiness
  `/health/ready` (codecentric keycloakx 7.2.3 defaults; probes are templated string
  values — verified against the upstream statefulset template, rendered under
  `{{- if .Values.health.enabled }}`).

## Design decisions

1. **Self-heal via the container's own health check** (user directive). Keycloak's
   `/health` endpoints cannot reflect MQTT state (no SPI hook for custom health), so
   the liveness probe checks an observable side effect of a healthy client: an
   ESTABLISHED TCP socket to the broker. Port 1883 = `0x075B` hex, TCP state `01` =
   ESTABLISHED, readable from `/proc/net/tcp{,6}` inside the container.
2. **Probe ordering matters:** check `/proc/net/tcp*` FIRST, then only test broker
   reachability — otherwise the probe's own test connection would self-match.
3. **Broker-unreachable pass-through:** if the broker can't be reached, restarting
   keycloak cannot help, so the probe passes — this prevents a crashloop during HA
   outages (keycloak keeps serving logins; when HA returns, the wedged client makes
   the probe fail and one healing restart happens).
4. **This also plugs paho's second hole:** paho never retries a failed INITIAL
   connect at boot; the probe catches that state too (no socket + broker reachable).
5. **Readiness untouched:** an MQTT problem must never remove keycloak from its
   Service; only liveness (restart) reacts. Startup probe unchanged (gates liveness
   through the ~1–5 min boot; the MQTT connect happens during JVM init).
6. **The ArgoCD rollout of this change IS the restore:** rolling keycloak reconnects
   MQTT and installs the watchdog in one restart.
7. **Rejected alternatives** (with reasons): JAR swap/upgrade (already 22.0.0;
   reconnect empirically broken), Java rewrite of the in-repo listener
   (disproportionate), CronJob watchdog (user declined), DB-polling of the JPA event
   store (kept as fallback if the probe heuristic proves flaky).
8. **Accepted trade-offs:** ~1 keycloak restart per HA/broker blip (new SSO logins
   blip ~30–90s; sessions persist in Postgres; ~8 blips/month observed); a
   ≤keepalive "connected-but-stale" window before paho itself notices; socket
   presence is a heuristic for client health.

## Changes

### 1. `charts/keycloakx/values.yaml` — MODIFY (only file touched)

Under the existing `keycloakx:` block, add/override `livenessProbe` (templated string,
per codecentric chart mechanics). Leave `startupProbe`/`readinessProbe` at chart
defaults.

```yaml
keycloakx:
  # ... existing values (image, command, database, proxy, extraEnv, ...) ...

  # MQTT watchdog: the Keycloak MQTT event-listener client (paho) dies whenever the
  # Home Assistant MQTT broker restarts and never recovers (verified 2026-09-27:
  # 8 disconnects, 0 auto-recoveries, 1801 failed publishes, 3 weeks of silent
  # external-SSO lockout). A healthy client holds an ESTABLISHED TCP connection to
  # the broker; a wedged one holds none. This probe makes the kubelet restart the
  # container in that state — boot always reconnects cleanly (0 boot failures in
  # 30d of logs). Broker-unreachable passes, so HA outages don't crashloop us.
  livenessProbe: |
    exec:
      command:
      - /bin/bash
      - -c
      - |
        # 1) Healthy = ESTABLISHED connection to the MQTT broker exists.
        #    1883 = 0x075B; st 01 = ESTABLISHED. Checked FIRST so the probe's own
        #    reachability test below can never self-match.
        if awk '$4=="01" && $3 ~ /:075B$/' /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -q .; then
          exit 0
        fi
        # 2) No socket. If the broker itself is unreachable, a restart can't help
        #    (and would crashloop during HA outages) — pass.
        timeout 3 bash -c 'exec 3<>/dev/tcp/mqtt.spencerslab.com/1883' 2>/dev/null || exit 0
        # 3) Broker reachable but keycloak holds no connection — client is wedged.
        exit 1
    periodSeconds: 30
    timeoutSeconds: 10
    failureThreshold: 2
```

Nothing else changes. (If a future change moves the broker or port, update the hex
port/hostname here — noted in the comment.)

## Verification

Pre-merge (Code agent):
- `helm lint charts/keycloakx` and `helm template charts/keycloakx` must pass
  (dependency build first if needed). If helm is unavailable in the execution env,
  fall back to post-sync pod-spec verification below and say so explicitly.
- Eyeball the rendered StatefulSet in the template output: livenessProbe is the exec
  probe; startup/readiness still httpGet.

Post-sync (after user merges → ArgoCD rolls `infra-keycloakx`):
- `readonly-infra-kubernetes` → `pods_get infra-keycloakx-0`: livenessProbe shows the
  exec command; pod Ready; restarts settle (one extra restart from the rollout is
  expected).
- Loki (`readonly-global-grafana`): `Publishing failed` count stops growing after the
  rollout; no `Connection could not be established`.
- Probe self-test (USER, one-off):
  `kubectl --context infra -n default exec infra-keycloakx-0 -- bash -c '<same script>'; echo $?`
  → expect `0` while the client is connected.
- End-to-end (USER): log in externally once → sidecar logs
  `Processing LOGIN: user=… ip=…` within seconds
  (`readonly-proxy-local-kubernetes` pods_log, container `user-allowlist-mqtt`) →
  boards/player/audiobook-player work externally.
- Self-heal proof (next HA/broker restart): Loki shows `MQTT Ping … Timed out`,
  within ~3–4 min the pod restart counter increments, and publishes resume
  (sidecar `Processing LOGIN` on the next login) — no manual intervention.

## Risks & open questions

- **bash in the KC image:** quay.io/keycloak/keycloak is UBI-based and expected to
  include bash; the probe self-test above confirms. Fallback if absent: same logic in
  `sh`+awk only (drop the reachability test or implement via awk on /dev/tcp-less
  shells — decide only if needed).
- **Heuristic edges:** IPv6 sockets covered via `/proc/net/tcp6`; the awk header line
  can't match (`st` ≠ `01`); transient reconnect flashes may pass the probe early —
  `failureThreshold: 2` + 30s period require a persistent failure before restart.
- **Restart storms:** mitigated by the broker-unreachable pass-through; kubelet
  CrashLoopBackOff is the backstop if the probe is ever wrong.
- **If the heuristic misbehaves:** fallback is the DB-poll design (sidecar polls the
  Keycloak JPA `EVENT_ENTITY` table; JPA event store is active — evidenced by
  `JpaEventStoreProvider` timer logs). Not part of this change.
- **Follow-ups (deferred, still valid):** Loki alert on `Publishing failed` /
  sidecar event-starvation (detection even if probes are ever disabled); sidecar
  expiry bugs in `containers/traefik-mqtt-allowlist/main.py` (existing-IP logins
  never refresh `expires:`; cleanup only on new-IP events); proxy-remote edge gaps
  (documents/music-player/git missing routers; pictaria/draw/edms/training/erp/forms
  no entries — user-deferred); hub TLS noise (cluster-wildcard-cert, scifi-farm-cert).
