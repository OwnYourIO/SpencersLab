# Plan: Fix external SSO outage — Keycloak MQTT event publisher dead, remote IP allowlist stale

Type: bug. Date: 2026-09-27. Affects: boards/player/audiobook-player (and every
hub service gated by Keycloak forward-auth or the IP allowlist) from the public
internet. Internal (LAN/mesh) access unaffected.

## Goal

External users can log in through Keycloak again: after an SSO login, their
current remote IP lands in `user-allowlist-remote` within seconds, so
boards.spencerslab.com, player.spencerslab.com, audiobook-player.spencerslab.com
(and all other gated hosts) stop bouncing 403→307 in a login loop. The event
pipeline is made resilient to Home Assistant / MQTT-broker restarts so this
cannot silently recur.

## Skills

- `kubernetes-skill` — StatefulSet restart semantics, probe/readiness expectations
  for the keycloak restart step.
- (no Helm chart changes; no container-image build changes in CI — the Java JAR
  is hand-rsynced per its README, and the sidecar image change rides the normal
  `docker-build.yaml` tag flow if Phase 3 is done.)

## MCP Servers

- `readonly-infra-kubernetes` — verify keycloak pod (restarts, age, logs via Loki).
- `readonly-proxy-local-kubernetes` — hub traefik + `user-allowlist-mqtt` sidecar logs.
- `readonly-global-grafana` — Loki queries for verification (uid `P8E80F9AEF21F6940`).
- No `admin-*` servers: all cluster mutations below are user-executed kubectl.
  (`admin-infra-kubernetes` exists in agent-config.jsonc but is `enabled: false`.)

## Verified context (diagnosis, all evidenced 2026-09-27)

**Symptom:** internally everything works; externally, anonymous/SSO-redirect
public paths work (polls invite links, paste, login realm JSON) but every host
that requires Keycloak login or the remote IP allowlist fails:

- External probes to boards/player/audiobook-player/documents/etc. → 307 →
  login.spencerslab.com; Keycloak auth endpoint answers 200 (login form) for
  client_id wekan/jellyfin/audiobookshelf.
- Today 16:16 UTC the user (`thehackmeister`) completed a real Keycloak LOGIN
  for player.spencerslab.com from **172.59.224.188** — visible in Loki
  (`{service_name="keycloakx"}` org.keycloak.events DEBUG).
- Immediately after that event:
  `SEVERE [org.softwarefactory.keycloak.providers.events.mqtt.MQTTEventListenerProvider]
  Publishing failed!: Client is not connected (32104)`.

**Root cause chain:**

1. The allowlist that gates external access (`/data/user-allowlist.yaml` on the
   hub traefik, middlewares `user-allowlist` + `user-allowlist-remote`) is
   maintained by the `user-allowlist-mqtt` sidecar
   (`ghcr.io/ownyourio/traefik-mqtt-allowlist:0.0.12`) from Keycloak LOGIN
   events arriving on MQTT topic `keycloak`.
2. Keycloak publishes those events with a third-party listener JAR on the
   `keycloak-providers` PVC: `org.softwarefactory.keycloak.providers.events.mqtt`
   (configured via `KC_SPI_EVENTS_LISTENER_MQTT_*` env in
   `charts/keycloakx/templates/secret-keycloak-admin.yaml`; broker
   `tcp://mqtt.spencerslab.com:1883` = **Home Assistant's embedded MQTT broker**,
   retained=true, QoS0).
3. That paho client died **2026-09-10 04:06 UTC** ("Timed out as no write
   activity, keepAlive=60s" — broker restart, consistent with an HA
   update/restart; a previous instance died ≥ 2026-09-06 19:15, oldest visible
   failure, 1801 `Publishing failed` events in 30d). It has **no
   auto-reconnect** → every LOGIN since fails to publish.
4. Sidecar therefore saw zero real events since early September (the two
   "INTROSPECT_TOKEN" messages it logged on 09-24/09-25 were the stale
   `retained` message replayed on (re)subscribe). No new remote IPs added for
   ~3 weeks; the user's current IP 172.59.224.188 is not allowlisted.
5. Result: external request → hub `<name>-ingress` chain crowdsec →
   redirect-on-status → `user-allowlist-remote` → **403** → redirect plugin →
   307 back to login → infinite SSO loop. Internal works because
   `user-allowlist` includes `10.0.0.0/16` by default.
6. Corroborating dead ends ruled out: hub traefik healthy (v4 probe fixes in
   place, plugins loaded, file provider OK); edge TLS/DNS/tunnel fine for
   working hosts; `oidc-keycloak` middleware works hub-side; Keycloak itself
   healthy. (Separate, pre-existing: documents/music-player/git have no edge
   routers, and pictaria/draw/edms/training/erp/forms have no proxy-remote
   entries — user deferred those; not this fix.)

**Key files:**

- `src/java/keycloak-to-traefik/` — in-repo Keycloak listener (provider id
  `keycloak-to-traefik-login-listener`): on LOGIN/REGISTER it writes
  `/data/user-allowlist.yaml` **inside the keycloak pod** — dead path (the pod
  has no `/data` mount; verified live spec) — plus a "new IP" admin email.
- `containers/traefik-mqtt-allowlist/main.py` — the live writer (sidecar next
  to hub traefik; shared PVC `proxy-allowlist`).
- `charts/traefik/values.yaml` — sidecar wiring, file provider at `/data/`.
- `charts/keycloakx/templates/secret-keycloak-admin.yaml` — MQTT SPI env.
- Broker: Home Assistant embedded MQTT (HA 2026.9.2 RUNNING, verified via
  readonly-global-homeassistant). `home-mosquitto` pod exists but is NOT the
  broker in use (user-confirmed).

## Design decisions

1. **Restore first, harden second.** Restarting keycloak re-initializes the
   softwarefactory paho client (reconnects to the healthy HA broker) → events
   flow again within seconds. Zero code risk, unblocks the user immediately.
2. **Fix the permanent fragility in the in-repo listener** (add MQTT publish
   with `setAutomaticReconnect(true)` + publish retry), then retire the
   third-party JAR. Rationale: repo already owns a listener that fires on the
   right events; replacing an opaque binary JAR with in-repo code makes this
   debuggable/patchable. Env vars are reused as-is (`KC_SPI_EVENTS_LISTENER_MQTT_*`
   read via `System.getenv`) → **no chart/values changes**.
3. Keep the sidecar architecture (Keycloak never writes traefik's PVC
   cross-cluster; MQTT decouples the clusters). Remove the dead in-pod
   `/data/user-allowlist.yaml` file-writing code (misleading; the mount doesn't
   exist).
4. Publish with **retained=false** and QoS 1 (retained=true is what kept
   replaying a stale Sept event and masking the outage in sidecar logs).
5. Phase 3 (optional): fix the sidecar's expiry bugs — (a) existing-IP logins
   early-return without refreshing `expires:` (entry dies 30d after FIRST add
   even with daily use), (b) expired-entry cleanup only runs when a NEW IP
   logs in, and can then evict a still-active expired IP.
6. Not in scope (user-deferred): edge ingress gaps (documents/music-player/git
   missing routers; pictaria/draw/edms/training/erp/forms no entries); hub TLS
   noise (cluster-wildcard-cert, scifi-farm-cert); stale git/help DNS.

## Changes

### Phase 0 — Immediate restore (USER executes; no code needed)

0.1 Restart Keycloak so the MQTT listener reconnects (brief SSO-login blip;
    existing sessions survive — they're in Postgres):

    kubectl --context infra -n default rollout restart statefulset/infra-keycloakx
    kubectl --context infra -n default rollout status statefulset/infra-keycloakx

0.2 (Optional instant unblock, skips waiting for 0.1 to settle) add the user's
    current IP to the allowlist directly — the traefik image has no shell, use
    the python sidecar container (file provider watch reloads ~instantly):

    POD=$(kubectl --context <proxy-local> -n kube-system get pod -l app.kubernetes.io/name=traefik -o name | head -1)
    kubectl --context <proxy-local> -n kube-system exec $POD -c user-allowlist-mqtt -- python3 - <<'PY'
    import datetime, pathlib
    p = pathlib.Path('/data/user-allowlist.yaml')
    c = p.read_text()
    now = datetime.datetime.now()
    entry = '          - "172.59.224.188" # user: thehackmeister, last-login: %s, expires: %s\n' % (
        now.isoformat(timespec='seconds'), (now + datetime.timedelta(days=30)).strftime('%Y-%m-%d'))
    assert entry.split('"')[1] not in c, "IP already present"
    p.write_text(c.replace('          # END ALLOWLIST AUTOMATION', entry + '          # END ALLOWLIST AUTOMATION'))
    print("added")
    PY

0.3 Verify: user retries boards/player/audiobook-player externally; log in once;
    retry if the very first callback races the file write.

### Phase 1 — Repo source changes (CODE agent)

1. `src/java/keycloak-to-traefik/pom.xml` — [MODIFY]
   - Add dependency `org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5`
     (compile scope).
   - Add `maven-shade-plugin` (3.5.x) bound to `package` phase so the JAR is
     self-contained (Keycloak does not bundle paho). Keep
     `finalName: keycloak-to-traefik-login-listener`.

2. `src/java/keycloak-to-traefik/src/main/java/com/keycloaktotraefik/logineventlistener/provider/LoginEventListenerProvider.java` — [MODIFY]
   - Remove the dead direct-file code paths: `ALLOWLIST_FILE_PATH`,
     `ensureAllowlistFileExists()`, `updateUserAllowlist()`, `processAllowlist()`
     and their use in `onEvent` (keep the `isNewIp` decision by another means —
     see next bullet).
   - Add a static/lazy paho `MqttClient` initialized from
     `System.getenv("KC_SPI_EVENTS_LISTENER_MQTT_SERVER_URI" / "_USERNAME" /
     "_PASSWORD" / "_TOPIC" / "_PUBLISHER_ID")` with:
     `setAutomaticReconnect(true)`, keepAlive 30s, `connect()` guarded +
     re-`connect()` on publish failure, QoS 1, `retained=false`.
   - On LOGIN/REGISTER publish JSON compatible with the sidecar parser:
     `{"type":"LOGIN","ipAddress":"<event.getIpAddress()>","details":{"username":"<username>"}}`
     (sidecar `main.py` requires exactly `type`, `details.username`, `ipAddress`).
   - Keep `sendNewIpNotificationEmail` but derive "new IP" from the LAST event
     seen per user (simple in-memory map is fine; email is best-effort) OR drop
     the new-IP gating and email on every LOGIN — simplest: keep a
     `ConcurrentHashMap<String,String> lastIpByUser`.
   - All MQTT work must be async/non-blocking or wrapped in try/catch so an
     outage never blocks the login request.

3. `src/java/keycloak-to-traefik/README.md` — [MODIFY]
   - Document: this JAR now ALSO publishes LOGIN/REGISTER events to MQTT
     (replaces the softwarefactory mqtt listener); build
     (`mvn clean package`), rsync the shaded jar to
     `/var/lib/rancher/k3s/storage/pvc-ccdc073d-f452-40f8-83de-dd144a31633c_default_keycloak-providers/`,
     **delete** the softwarefactory JAR(s) from the same directory, then
     `kubectl -n default rollout restart statefulset/infra-keycloakx`.

### Phase 2 — Build & deploy (USER executes, per README)

2.1 `mvn clean package` (needs JDK17 + maven — not available in agent env).
2.2 rsync new JAR to the providers PVC dir on the infra node; remove the
    `mqtt`/softwarefactory JAR; restart the keycloak StatefulSet.
2.3 Confirm startup log shows both factories registering and NO `Publishing
    failed` afterward (Loki).

### Phase 3 — Sidecar hardening (CODE agent, optional but recommended)

4. `containers/traefik-mqtt-allowlist/main.py` — [MODIFY]
   - In `_update_allowlist`: when the IP already exists, refresh its
     `last-login:`/`expires:` fields instead of early-returning (mirror the
     Java semantics).
   - Run the expired-entry sweep on EVERY event (currently only on new-IP add)
     and never evict entries younger than their parsed expiry.
   - Image change ships via `docker-build.yaml` (`:v<run>` + `:main`); the
     chart pin `ghcr.io/ownyourio/traefik-mqtt-allowlist:0.0.12` updates when a
     new release tag is cut (renovate) — call this out; do NOT hand-edit tags.

## Verification

Phase 0:
- Loki: `count_over_time({service_name="keycloakx"} |= "Publishing failed" [15m])`
  stops growing ~immediately after the keycloak restart (allow a few final
  events during rollout).
- User logs in externally once → sidecar log shows
  `Processing LOGIN: user=thehackmeister ip=172.59.224.188`
  (`readonly-proxy-local-kubernetes` pods_log, container `user-allowlist-mqtt`).
- boards/player/audiobook-player load externally for the user.

Phase 2:
- Same Loki checks; plus trigger a login and confirm the sidecar line appears
  within seconds (retain=false also means no stale replay after sidecar
  reconnects).

Phase 3:
- Unit-style check: run `python3 containers/traefik-mqtt-allowlist/main.py`
  logic mentally / with a fake event — existing-IP event updates expiry in the
  emitted YAML.

## Risks & open questions

- **Build toolchain:** agent env has no java/mvn/docker — Phase 2 is
  user-executed by design. If the shaded JAR collides with Keycloak-provided
  classes, shade only `org.eclipse.paho` (relocations possible).
- **HA broker volatility:** any HA restart still briefly drops the client; with
  `setAutomaticReconnect(true)` + publish-retry this self-heals in seconds. If
  HA's embedded broker proves unstable, consider pointing
  `KC_SPI_EVENTS_LISTENER_MQTT_SERVER_URI` at the (currently unused)
  home-mosquitto — decision for the user.
- **3-week backfill:** other users locked out during the outage self-heal on
  their next login attempt (first attempt loops once, LOGIN event adds the IP,
  retry succeeds). No manual backfill needed unless someone cannot log in at
  all (then add their IP as in 0.2).
- **Realm event config:** if LOGIN events ever stop appearing in Loki after a
  Keycloak upgrade, check Realm → Events → Event listeners includes
  `keycloak-to-traefik-login-listener` (and previously `mqtt`).
- **Follow-up (separate work):** observability — Loki alert on
  `Publishing failed` (keycloakx) and on sidecar event-starvation (>7d without
  `Processing LOGIN`); the deferred proxy-remote edge gaps
  (documents/music-player/git routers; pictaria/draw/edms/training/erp/forms
  entries).
