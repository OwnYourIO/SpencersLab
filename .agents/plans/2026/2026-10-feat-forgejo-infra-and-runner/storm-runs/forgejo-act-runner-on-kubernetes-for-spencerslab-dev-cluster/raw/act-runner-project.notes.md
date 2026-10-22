# Interview — act_runner / forgejo-runner project

Interviewed 2026-10-21 (inline, single session); runner v13.2.0 source
re-verified from the Go module proxy zip on 2026-10-21.

## Q1: What image do we pin, and what is the release cadence?

The project was renamed `act_runner` → `forgejo/runner` (binary
`forgejo-runner`); the GitHub mirror is gone — the repo lives only on
code.forgejo.org [2][4]. The container image is published as
`data.forgejo.org/forgejo/runner` (official docs) while community examples
use `code.forgejo.org/forgejo/runner` — same image, two registry hosts
[1][4][5]. Tags verified via the registry API: full semver plus short
aliases (`13.2.0`, `13.2`, `13`). Latest is **13.2.0** [1].

Release dates (releases API): v12.13.2 2026-07-23, v13.0.0 2026-08-03,
v13.1.0 2026-08-31, v13.2.0 2026-09-18 [2] — roughly a 2–4 week cadence, and
runner majors are NOT aligned to server majors (server 15.x ↔ runner 13.x).

**v13.0.0 is a breaking major** (2026-08-03 blog post) [3]:
- `GITEA_DEBUG`, `GITEA_TRACE`, `GITEA_RUNNER_CAPACITY`, `GITEA_RUNNER_FILE`,
  `GITEA_RUNNER_ENVIRON`, `GITEA_RUNNER_ENV_FILE` env vars now ignored.
- `container.network_mode` removed → `container.network`.
- Workflow commands `add-path`, `set-output`, `set-env` removed (write to
  `$FORGEJO_PATH` / `$FORGEJO_OUTPUT` / `$FORGEJO_ENV` instead); cannot be
  re-enabled with `ACTIONS_ALLOW_UNSECURE_COMMANDS`.
- `DOCKER_USERNAME`/`DOCKER_PASSWORD` secrets no longer used for registry
  auth → `jobs.<job_id>.container.credentials`.
- **Docker minimum raised to 25.0**; Docker 28.0.1+ recommended (IPv6 bug
  moby#49520/#52991 fixed there).
- `${{ gitea.[...] }}` context removed.

## Q2: What is the image like, and what does it need on disk?

v13.2.0 Dockerfile (read from source): `data.forgejo.org/oci/alpine:3.24`,
`apk add git bash dumb-init`, `ENV HOME=/data`, `USER 1000:1000`,
`WORKDIR /data`, `VOLUME ["/data"]`, `ENTRYPOINT ["/usr/bin/dumb-init"]`,
`CMD ["/bin/forgejo-runner"]` [4]. So: unprivileged by default, all state
under `/data` (which must be persistent to keep the `.runner` identity), and
no registration baked into the image.

Renovate: the repo already renovates runner references elsewhere (MASH role);
annotation form `# renovate: datasource=docker depName=data.forgejo.org/forgejo/runner versioning=semver`,
pinning full semver `13.2.0` [1].

## Q3: How does v13 register, and what does `.runner` hold?

`forgejo-runner register` and `create-runner-file` are **deprecated**:
"`register` has been deprecated; declare connections in the runner
configuration instead" (register.go:40) [4]. v13 registers over the gRPC
actions-proto (`runnerv1.Register`), not the old HTTP token exchange [4].

The `.runner` file (default path, `runner.file: .runner`) is JSON
`{WARNING, id, uuid, name, token, address, labels}` [4]. Persisting it is
what makes a restart a **re-attach** rather than a re-registration. Conflict
rules from source: a `.runner` file plus `server.connections` in config is an
error; flags plus `server.connections` is an error [4].

Declarative options (both valid):
- config `server.connections.dev: {url, uuid, token | token_url:
  file:$CREDENTIALS_DIRECTORY/token, labels, ...}` — `CREDENTIALS_DIRECTORY`
  is substituted by the runner (config.go) [4];
- or flags `--url --uuid --token-url --label` (config file optional;
  `daemon` requires at least one connection) [4].

The register default label is `docker:docker://data.forgejo.org/oci/node:lts`
[4][5].

Ephemeral runners: the register path errors with "This Forgejo instance does
not support ephemeral runners; requires Forgejo 15 or newer…" (register.go:357)
and daemon mode refuses ephemeral connections entirely (daemon.go:84) [4] —
ephemeral is a one-shot-job concept, not a daemon mode.

## Q4: What is the full config surface?

`internal/pkg/config/config.example.yaml` (v13.2.0, read in full) [4]:
- `runner`: `file: .runner`, `capacity: 1`, `envs`, `env_file`,
  `timeout: 3h` (server also has its own 3h job timeout),
  `shutdown_timeout: 3h`, `insecure`, `fetch_timeout: 30s`,
  `fetch_interval: 2s`, `report_interval: 1s`, `report_retry`, `labels`
  (supports `?platform=` suffix and the `label: image` mapping form).
- `cache`: `enabled: true`, `port: 0` (auto), `dir: $HOME/.cache/actcache`,
  `external_server`, `secret` / `secret_url` (`file:` + `$CREDENTIALS_DIRECTORY`),
  `host`, `proxy_port`, `actions_cache_url_override`.
- `container`: `network: ""` (auto), `enable_ipv6`, `privileged: false`
  (comment: "privileged mode is required for Docker-in-Docker"), `options`,
  `workdir_parent: /workspace`, `valid_volumes` (glob),
  `docker_host: "-"` (**default = no docker socket into job containers**;
  `automount` or `unix://…`/`ssh://` to opt in), `force_pull`,
  `force_rebuild`.
- `host`: `workdir_parent: $HOME/.cache/act/`.
- `server.connections`: per-connection `url`, `uuid`, `token`/`token_url`,
  `labels`, `fetch_interval`.

Relevant env vars: `DOCKER_HOST`, `CREDENTIALS_DIRECTORY`,
`FORGEJO_CLIENT_TIMEOUT` [4].

## Q5: What is the official Kubernetes example, and is it trustworthy?

`examples/kubernetes/dind-docker.yaml` in v13.2.0 [4]: Deployment
`replicas: 2`; a per-pod initContainer runs the deprecated `register` CLI in
a retry loop with `RUNNER_NAME` from `metadata.name`; DinD sidecar is
privileged `docker.io/docker:28.3.0-dind` with `DOCKER_TLS_CERTDIR=/certs`;
the runner container is hardened (non-privileged). **All volumes are
emptyDir** — so every pod recreation registers a brand-new runner and stale
runners accumulate in the server UI. The example also pins the stale runner
tag `6.4.0`. Verdict: useful for mechanism (initContainer registration loop,
TLS socket), not for the persistence model or the tag.
