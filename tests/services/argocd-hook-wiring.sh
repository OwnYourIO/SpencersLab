#!/usr/bin/env bash
# argocd-hook chart + proxy-local service trio contract (2026/2026-11-cf-139-feat-argocd-webhook-sync, C02):
# charts/argocd-hook (bjw-s app-template 5.0.1) consuming the C01 image, wired
# through the trio — services/proxy-local charts: entry + crowdsec-only
# argocd-hook subdomain + ExternalSecret bitwardenIds with the custom-values
# OVERRIDE_NEEDED sentinels shipped through the merge (OQ5 ruling).
#
# C02-fix (rulings R1/R4) re-pin: the HMAC ExternalSecret secretKey renames
# to hook-secret — byte-equal to the relay's new flat filename (a mismatch
# is a startup ConfigError crash-loop, visible, in the SAME release). The
# tokens ES, bitwardenIds keys, trio entries, clusterHosts map, allowedRefs
# and the trackedRepo VALUE all stay untouched — the chart README and the
# values comment gain the main-sync origin framing, trackedRepo keeps the
# GitHub URL because the fleet's live app sources still read GitHub 9/9 and
# app_matches byte-compares THAT, never the payload's repository field
# (R1 option (c); flipping early is the silent skipped-x11 no-op trap).
#
# Contract source: chunks/C02-fix.md "## Tests". AC trace:
# t1[AC1] t2[AC1+AC2 render legs] t3[AC2/AC3] t4[AC2+R4 doc/sentinel pairing]
# t5[AC2 diff scope tightened] t6[AC6+AC7]
#
# Helm ladder per tests/services/dev-mcp-fleet.sh: HELM_BIN -> PATH ->
# ~/.local/bin -> find -> pinned download; the chart renders from a COPY under
# /tmp/opencode after `helm dependency update` (the worktree is never written);
# registry-unreachable => the render-dependent legs skip with a warning, never
# a false green. The render is additionally content-guarded (a workload + the
# targets ConfigMap must be present) — FRICTION 2026-11-12: a chart rendered
# without vendored deps emits ZERO objects and an empty render would otherwise
# pass every grep vacuously.
#
# Release name: the appset-charts Application for this chart is
# `<cat>-<app>` = proxy-local-argocd-hook (DECISIONS/EXPLORE §2), and the hub
# subdomain entry consumes exactly that helm release's Service, so the harness
# renders with that release name — the bare chart name would render a Service
# object no deploy ever creates and AC3's equality would test fiction.
#
# Run from the repo root:
#   bash tests/services/argocd-hook-wiring.sh           # t1..t6
#   bash tests/services/argocd-hook-wiring.sh t4 t5     # subset
# Env: CHUNK_BASE=<ref> for the t5 scope diff (review passes the pre-chunk
#      commit; default HEAD); HELM_BIN to force the helm binary.
set -euo pipefail
export PATH=$HOME/.local/bin:$PATH   # FRICTION seed: helm is not on PATH here

cd "$(git rev-parse --show-toplevel)"

CHART="${HOOK_CHART:-charts/argocd-hook}"
PROXY_VALS="${HOOK_PROXY_VALS:-services/proxy-local/prod/values.yaml}"
CV="${HOOK_CUSTOM_VALUES:-custom-values/proxy-local/prod-values.yaml}"
RELEASE="proxy-local-argocd-hook"
TEST_UUID="test-uuid"
DOMAIN="test.example.com"
TRACKED_REPO="https://github.com/OwnYourIO/SpencersLab.git"
# t4's cross-suite parity leg reads the relay README (test may read any
# surface; the agreement pin lives here because C02-fix gates both docs).
CONT_README="${HOOK_CONTAINER_README:-containers/argocd-hook/README.md}"
# Full path, not basename: the final review caught a plans-folder pointer to
# the same filename — a basename grep passed it green while the path was dead.
RUNBOOK=".agents/notes/2026-11-17-argocd-hook-relay.md"
BASE="${CHUNK_BASE:-HEAD}"
CATS="dev gpu gpu-ai grow home infra media monitoring proxy-local proxy-backup proxy-remote"

checks=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ok() {
  checks=$((checks + 1))
  printf 'ok: %s\n' "$1"
}

skip() {
  printf 'skip: %s\n' "$1" >&2
}

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in $(seq 1 6); do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t[1-6]$ ]] || fail "unknown test id '$a' (expected t1..t6)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

command -v python3 >/dev/null 2>&1 || fail "python3 (+pyyaml) is required for the values/render walks"

# --- test-scope dirs ----------------------------------------------------------
[ -d "$CHART" ] ||
  fail "$CHART does not exist — C02 (chart + trio) is not implemented"
[ -f "$PROXY_VALS" ] || fail "$PROXY_VALS missing (the hub's own values file must exist to be wired)"
[ -f "$CV" ] || fail "$CV missing (custom-values half of the trio)"

# --- helm discovery (dev-mcp-fleet recipe) -------------------------------------
find_helm() {
  # Each branch prints exactly one path AND returns 0 — a missing return
  # concatenates a second path into the result (F01 review finding on that
  # precedent).
  local cand
  if [ -n "${HELM_BIN:-}" ] && [ -x "${HELM_BIN}" ]; then
    printf '%s' "$HELM_BIN"
    return 0
  fi
  if command -v helm >/dev/null 2>&1; then
    command -v helm
    return 0
  fi
  if [ -x /home/coder/.local/bin/helm ]; then
    printf '%s' "/home/coder/.local/bin/helm"
    return 0
  fi
  cand=$(find /tmp/opencode -maxdepth 4 -type f -name helm -perm -u+x 2>/dev/null | head -n 1 || true)
  if [ -n "$cand" ]; then
    printf '%s' "$cand"
    return 0
  fi
  return 1
}

download_helm() {
  local version=3.21.4 arch dir tar expected
  command -v curl >/dev/null 2>&1 || return 1
  command -v tar >/dev/null 2>&1 || return 1
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  dir=/tmp/opencode/argocd-hook-wiring-helm-download
  mkdir -p "$dir"
  tar="$dir/helm-v${version}-linux-${arch}.tar.gz"
  curl -fsSL --max-time 120 -o "$tar" \
    "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz" >/dev/null 2>&1 || return 1
  curl -fsSL --max-time 30 -o "${tar}.sha256sum" "https://get.helm.sh/helm-v${version}-linux-${arch}.tar.gz.sha256sum" >/dev/null 2>&1 || return 1
  (cd "$dir" && sha256sum -c "$(basename "$tar").sha256sum" >/dev/null 2>&1) || return 1
  tar -xzf "$tar" -C "$dir" || return 1
  expected=$(find "$dir" -type f -name helm -perm -u+x | head -n 1 || true)
  [ -n "$expected" ] || return 1
  printf '%s' "$expected"
}

helm_bin=$(find_helm || true)
[ -n "$helm_bin" ] || helm_bin=$(download_helm || true)

WORK=$(mktemp -d /tmp/opencode/argocd-hook-wiring.XXXXXX)

# --- shared render (t1,t2,t3,t6) -----------------------------------------------
# One dependency-updated copy + one canonical render (plan Commands values),
# plus the allowedRefs-override render for t3's config-driven leg.
RENDER=""
RENDER2=""
SKIP_RENDER=0
if want t1 || want t2 || want t3 || want t6; then
  if [ -z "$helm_bin" ]; then
    skip "no helm binary on PATH, in ~/.local/bin, or downloadable; t1-t3 and the t6 render legs were not run"
    SKIP_RENDER=1
  else
    chart_copy="$WORK/chart-copy"
    cp -R "$CHART"/. "$chart_copy"/
    dep_log="$chart_copy/dependency-update.log"
    if ! (cd "$chart_copy" && "$helm_bin" dependency update .) >"$dep_log" 2>&1; then
      if grep -qiE 'dial tcp|no such host|connection refused|TLS handshake|network is unreachable|Failed to download|failed to fetch|could not download' "$dep_log"; then
        skip "helm dependency update could not reach the chart repo here; t1-t3 and the t6 render legs were not run (log kept at $dep_log)"
        SKIP_RENDER=1
      else
        tail -n 30 "$dep_log" >&2
        fail "helm dependency update failed for $CHART (log kept at $dep_log)"
      fi
    fi
    if [ "$SKIP_RENDER" -eq 0 ]; then
      lint_log="$WORK/lint.log"
      if ! "$helm_bin" lint "$chart_copy" >"$lint_log" 2>&1; then
        tail -n 30 "$lint_log" >&2
        fail "t1: helm lint failed for $CHART (log kept at $lint_log)"
      fi
      RENDER="$WORK/render.yaml"
      render_err="$WORK/render.err"
      if ! "$helm_bin" template "$RELEASE" "$chart_copy" \
          --set "domain=$DOMAIN" \
          --set "bitwardenIds.argocd-hook-secret=$TEST_UUID" \
          --set "bitwardenIds.argocd-hook-tokens=$TEST_UUID" \
          >"$RENDER" 2>"$render_err"; then
        tail -n 30 "$render_err" >&2
        fail "t1: helm template of the $CHART copy failed (log kept at $render_err)"
      fi
      # Zero-render trap guard (FRICTION 2026-11-12 class): an un-vendored
      # dependency renders nothing and every downstream grep would pass on
      # emptiness — demand the objects C02 exists to produce.
      { [ -s "$RENDER" ] && grep -q 'kind: Deployment' "$RENDER" && grep -q 'kind: ConfigMap' "$RENDER"; } || {
        echo "--- render head ---" >&2; head -n 40 "$RENDER" >&2
        fail "t1: the render is empty or lacks the argocd-hook Deployment/ConfigMap (dependency not vendored, or chart mis-wired)"
      }
      RENDER2="$WORK/render-allowedrefs.yaml"
      if ! "$helm_bin" template "$RELEASE" "$chart_copy" \
          --set "domain=$DOMAIN" \
          --set "bitwardenIds.argocd-hook-secret=$TEST_UUID" \
          --set "bitwardenIds.argocd-hook-tokens=$TEST_UUID" \
          --set "allowedRefs[0]=refs/heads/main" \
          --set "allowedRefs[1]=refs/heads/stage" \
          >"$RENDER2" 2>"$WORK/render2.err"; then
        tail -n 20 "$WORK/render2.err" >&2
        fail "t3: the allowedRefs-override render failed — the value key must exist and flow into targets.json (OQ7: widening is one values edit)"
      fi
    fi
  fi
fi

# --- t1: lint + render hygiene (AC1) --------------------------------------------
if want t1; then
  if [ -z "$RENDER" ]; then
    skip "t1: lint/render not exercised (no usable helm or unreachable chart repo) — an empty t1 is NOT a pass"
  else
    ok "t1: helm lint passes for $CHART (AC1 — lint ran in the shared setup; a failure there is a hard fail)"
    if python3 - "$RENDER" <<'PY'
import sys, yaml

render = sys.argv[1]
raw = open(render).read()


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


if "OVERRIDE_" in raw:
    bad("t1: an OVERRIDE_* sentinel survives the render even with both bitwardenIds --set — a third placeholder was introduced or the two are not the ES sources (AC1)")

docs = [d for d in yaml.safe_load_all(raw) if d]
workloads = [d for d in docs if d.get("kind") in ("Deployment", "StatefulSet", "DaemonSet")]
containers = []
for w in workloads:
    pod = ((w.get("spec") or {}).get("template") or {}).get("spec") or {}
    containers += pod.get("containers") or []
if not containers:
    bad("t1: no workload containers in the render (AC1)")
c = containers[0]
if c.get("image") != "ghcr.io/ownyourio/argocd-hook:main":
    bad("t1: rendered image is %r, expected ghcr.io/ownyourio/argocd-hook:main (C02 image task — :main + Always is the sanctioned unpinned case until the first prod build ships a calendar tag)" % c.get("image"))
if c.get("imagePullPolicy") != "Always":
    bad("t1: imagePullPolicy is %r, expected Always (:main is mutable)" % c.get("imagePullPolicy"))
print("ok: t1 — zero OVERRIDE_* after --set; image ghcr.io/ownyourio/argocd-hook:main with pullPolicy Always (AC1)")
PY
    then
      ok "t1 render legs passed (AC1)"
    else
      fail "t1: render hygiene violated (reason printed above)"
    fi
  fi
fi

# --- t2: C01 contract plumbing + ExternalSecrets + mounts (AC2) -----------------
if want t2 && [ -n "$RENDER" ]; then
  if python3 - "$RENDER" "$RELEASE" "$TEST_UUID" <<'PY'
import re, sys, yaml

render, release, test_uuid = sys.argv[1:4]
docs = [d for d in yaml.safe_load_all(open(render)) if d]


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


workloads = [d for d in docs if d.get("kind") in ("Deployment", "StatefulSet", "DaemonSet")]
w = workloads[0]
pod = ((w.get("spec") or {}).get("template") or {}).get("spec") or {}
c = (pod.get("containers") or [{}])[0]

args = " ".join(str(a) for a in (c.get("args") or []) + (c.get("command") or []))
if not re.search(r"--config\s+\S*?/config/targets\.json", args):
    bad("t2: container args %r do not carry --config /config/targets.json (C01 CLI contract verbatim, AC2)" % args)
if not re.search(r"--secrets-dir\s+\S*?/secrets", args):
    bad("t2: container args %r do not carry --secrets-dir /secrets (C01 CLI contract verbatim, AC2)" % args)

env_names = {e.get("name") for e in (c.get("env") or [])}
for tunable in ("SETTLE_SECONDS", "TARGET_TIMEOUT_SECONDS"):
    if tunable not in env_names:
        bad("t2: container env lacks %s — the C01 tunables must be chart-wired, not left at code defaults nobody can set per cluster" % tunable)

ports = {p.get("name"): p.get("containerPort") for p in (c.get("ports") or [])}
for kind_probe in ("livenessProbe", "readinessProbe"):
    hg = ((c.get(kind_probe) or {}).get("httpGet") or {})
    if hg.get("path") != "/health":
        bad("t2: %s httpGet path is %r, expected /health (C01 handler contract, AC2)" % (kind_probe, hg.get("path")))
    resolved = hg.get("port")
    if isinstance(resolved, str):
        resolved = ports.get(resolved)
    if resolved != 8080:
        bad("t2: %s probes port %r (resolved %r), expected 8080" % (kind_probe, hg.get("port"), resolved))

es = [d for d in docs if d.get("kind") == "ExternalSecret"]
if len(es) != 2:
    bad("t2: expected exactly 2 ExternalSecrets (HMAC + tokens), got %d: %s" % (len(es), [(d.get("metadata") or {}).get("name") for d in es]))
es_info = []
for e in es:
    spec = e.get("spec") or {}
    target = ((spec.get("target") or {}).get("name"))
    data = spec.get("data") or []
    keys = {d.get("secretKey") for d in data}
    for d in data:
        rr = d.get("remoteRef") or {}
        if rr.get("key") != test_uuid:
            bad("t2: ExternalSecret %s remoteRef.key is %r — the item id must come from the (test-set) bitwardenIds value, never hardcoded (AC2)" % (target, rr.get("key")))
    es_info.append({"name": ((e.get("metadata") or {}).get("name")), "target": target, "keys": keys,
                    "data": data})
# C02-fix/R4: the HMAC ES maps EXACTLY one key, hook-secret — the flat
# filename the relay reads from --secrets-dir (containers/argocd-hook-relay.sh
# make_fixtures writes the same name, and the relay's --check leg proves the
# pairing end to end). Renamed, not deleted: the leg still proves exactly ONE
# ES carries the login-item password, nothing else does, and no residual key
# of any name rides along.
old_fn = "github-" "webhook"  # the retired filename, split so this harness carries no old literal
hmac_es = [i for i in es_info if "hook-secret" in i["keys"]]
if len(hmac_es) != 1:
    bad("t2: no ExternalSecret maps the HMAC password to secretKey hook-secret (the flat filename the relay reads from --secrets-dir, R4); ES key sets: %r" % [{i["name"]: sorted(i["keys"])[:4]} for i in es_info])
for i in es_info:
    if old_fn in i["keys"]:
        bad("t2: an ExternalSecret still maps the retired '%s' secretKey (R4 rename ripple incomplete)" % old_fn)
if hmac_es[0]["keys"] != {"hook-secret"}:
    bad("t2: the HMAC ExternalSecret key set is %r, expected exactly {'hook-secret'} — one key, renamed, nothing added" % sorted(hmac_es[0]["keys"]))
for d in hmac_es[0]["data"]:
    sr = ((d.get("sourceRef") or {}).get("storeRef") or {})
    rr = d.get("remoteRef") or {}
    if sr.get("name") != "bitwarden-login" or rr.get("property") != "password":
        bad("t2: the hook-secret entry is store %r property %r, expected bitwarden-login/password — the rename must not disturb the login-item mapping (AC1 byte-shape otherwise identical)" % (sr.get("name"), rr.get("property")))
tokens_es = [i for i in es_info if i not in hmac_es]
CATS = ["dev", "gpu", "gpu-ai", "grow", "home", "infra", "media", "monitoring", "proxy-local", "proxy-backup", "proxy-remote"]
missing_tok = [c for c in CATS if not any(c in i["keys"] for i in tokens_es)]
if missing_tok:
    bad("t2: the tokens ExternalSecret has no flat secretKey for %s — C01 reads --secrets-dir/<tokenKey> by category name (C02 task: 'flat filenames win', pinned shape)" % missing_tok)

vols = pod.get("volumes") or []


def secret_names(v):
    names = []
    if (v.get("secret") or {}).get("secretName"):
        names.append(v["secret"]["secretName"])
    for src in ((v.get("projected") or {}).get("sources") or []):
        if (src.get("secret") or {}).get("name"):
            names.append(src["secret"]["name"])
    return names


mounted_secrets = set()
for v in vols:
    mounted_secrets.update(secret_names(v))
es_targets = {i["target"] for i in es_info}
unmounted = sorted(es_targets - mounted_secrets)
if unmounted:
    bad("t2: ExternalSecret target Secret(s) %s are rendered but never mounted — the relay reads files, so the pod must mount what the ES writes (AC2 'secret names match what the pod mounts')" % unmounted)
sec_mount = [m for m in (c.get("volumeMounts") or [])
             if (m.get("mountPath") or "") in ("/secrets",) or (m.get("mountPath") or "").startswith("/secrets/")]
if not sec_mount:
    bad("t2: no volumeMount covers /secrets (mounts: %s) — args promise a secrets dir the pod never materializes (AC2)" % [m.get("mountPath") for m in (c.get("volumeMounts") or [])])
cm_docs = [d for d in docs if d.get("kind") == "ConfigMap" and "targets.json" in ((d.get("data") or {}))]
if not cm_docs:
    bad("t2: no rendered ConfigMap carries a targets.json data key (C01 --config /config/targets.json, AC2)")
cm_names = {((d.get("metadata") or {}).get("name")) for d in cm_docs}
cm_vols = {v.get("name"): v["configMap"]["name"] for v in vols if (v.get("configMap") or {}).get("name")}
covers_config = False
for m in (c.get("volumeMounts") or []):
    mp = m.get("mountPath") or ""
    vol_cm = cm_vols.get(m.get("name"))
    if vol_cm in cm_names and (mp == "/config" or mp == "/config/targets.json" or (mp == "/config/targets.json" and m.get("subPath") == "targets.json")):
        covers_config = True
if not covers_config:
    bad("t2: no ConfigMap volume mounts to cover /config/targets.json (volumeMounts: %s; configMap volumes: %r)" % ([ (m.get("name"), m.get("mountPath"), m.get("subPath")) for m in (c.get("volumeMounts") or [])], cm_vols))
print("ok: t2 — args carry the C01 CLI verbatim; probes hit /health on 8080; SETTLE/TARGET_TIMEOUT env wired; the HMAC ES maps ONLY hook-secret through bitwarden-login/password, the tokens ES the 11 category keys, both sourcing the test bitwardenIds, no retired key name anywhere; ES targets are mounted and /config/targets.json resolves from the ConfigMap (AC2/C02-fix)")
PY
  then
    ok "t2 passed (AC2)"
  else
    fail "t2: the C01-contract plumbing is not satisfied (reason printed above)"
  fi
fi

# --- t3: Service equality + targets.json content (AC3) --------------------------
if want t3 && [ -n "$RENDER" ]; then
  if python3 - "$RENDER" "$RENDER2" "$PROXY_VALS" "$CHART/values.yaml" "$RELEASE" "$DOMAIN" "$TRACKED_REPO" <<'PY'
import json, re, sys, yaml

render, render2, proxy_vals_path, chart_values_path, release, domain, tracked_repo = sys.argv[1:8]


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


def load(path):
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}


CATS = ["dev", "gpu", "gpu-ai", "grow", "home", "infra", "media", "monitoring", "proxy-local", "proxy-backup", "proxy-remote"]
# Live-verified exceptions to the derived cluster.<cat>.<domain> route shape.
OVERRIDE_HOSTS = {"dev": "cluster.dev.scifi.farm",
                  "home": "cluster.home-lab.spencerslab.com"}

pv = load(proxy_vals_path)
sub = ((pv.get("proxy") or {}).get("subdomains") or {}).get("argocd-hook")
if not isinstance(sub, dict):
    bad("t3: no proxy.subdomains.argocd-hook entry in %s (AC3 pairs the hub entry against the render)" % proxy_vals_path)
if sub.get("service") != release or str(sub.get("port")) != "8080":
    bad("t3: hub entry is service=%r port=%r, expected %s / 8080 (the <category>-<app> release service — C02 task pins both sides to match)" % (sub.get("service"), sub.get("port"), release))

docs = [d for d in yaml.safe_load_all(open(render)) if d]
svcs = [d for d in docs if d.get("kind") == "Service"]
names = [(d.get("metadata") or {}).get("name") for d in svcs]
if release not in names:
    bad("t3: no Service named %s in the render (services: %s) — the deployed hub release's Service IS this name; a fullname override here orphans the hub route (AC3)" % (release, names))
svc = next(d for d in svcs if (d.get("metadata") or {}).get("name") == release)
ports = [(p or {}).get("port") for p in ((svc.get("spec") or {}).get("ports") or [])]
if 8080 not in ports:
    bad("t3: Service %s ports are %r, expected an 8080 entry (AC3)" % (release, ports))


def targets_of(path):
    for d in yaml.safe_load_all(open(path)):
        if d and d.get("kind") == "ConfigMap" and "targets.json" in (d.get("data") or {}):
            try:
                return json.loads(d["data"]["targets.json"])
            except ValueError as ex:
                bad("t3: the rendered targets.json is not valid JSON: %s" % ex)
    bad("t3: no ConfigMap with a targets.json key in the render")


blob = targets_of(render)
if blob.get("allowed_refs") != ["refs/heads/main"]:
    bad("t3: targets.json allowed_refs is %r, expected exactly ['refs/heads/main'] (OQ7 shipped default)" % (blob.get("allowed_refs"),))
roster = blob.get("targets")
if not isinstance(roster, list):
    bad("t3: targets.json has no targets LIST (shape: {allowed_refs, targets}, C01 config contract): %r" % (blob,))
got_names = sorted(e.get("name") for e in roster)
if got_names != sorted(CATS):
    bad("t3: roster names %s, expected exactly the 11 fleet categories %s (plan fan-out target roster)" % (got_names, sorted(CATS)))
cv = load(chart_values_path)
if cv.get("trackedRepo") != tracked_repo:
    bad("t3: chart values trackedRepo is %r, expected %r — the git origin ArgoCD tracks (C02 values task)" % (cv.get("trackedRepo"), tracked_repo))
locals_ = []
host_errs = []
for e in roster:
    n = e.get("name")
    if e.get("rootApp") != n:
        bad("t3: roster entry %s rootApp is %r, expected the category root app name %s" % (n, e.get("rootApp"), n))
    if e.get("tokenKey") != n:
        bad("t3: roster entry %s tokenKey is %r, expected %s (flat secret file per category)" % (n, e.get("tokenKey"), n))
    if e.get("repo") != tracked_repo:
        bad("t3: roster entry %s repo is %r, expected the trackedRepo value %r (spec-driven fan-out matches live app spec.source.repoURL against it)" % (n, e.get("repo"), tracked_repo))
    # Live-verified roster (final whole-plan review 2026-11-21, readonly Ingress
    # + DNS reads): the argocd-server route is cluster.<cat>.<domain> for nine
    # categories; dev's own domain annotation is scifi.farm and home's
    # clusterName is home-lab, so the derived form is a dead hostname on those
    # two — they arrive as fixed full hosts injected from chart values. An
    # override elsewhere (or none here) means the render diverges from the
    # routes that actually answer pushes.
    if n in OVERRIDE_HOSTS:
        want_url = "https://" + OVERRIDE_HOSTS[n]
        why = "fixed values-injected host — the derived cluster.<cat>.<domain> form does not resolve on this cluster"
    else:
        want_url = "https://cluster.%s.%s" % (n, domain)
        why = "derived mesh route (must track --set domain; no per-category override expected)"
    if e.get("url") != want_url:
        host_errs.append("%s: rendered %r, expected %r (%s)" % (n, e.get("url"), want_url, why))
    if e.get("local"):
        locals_.append(n)
if host_errs:
    bad("t3: roster URLs diverge from the live-verified argocd-server hosts (%s)" % "; ".join(host_errs))
if locals_ != ["proxy-local"]:
    bad("t3: entries flagged local: %s, expected exactly ['proxy-local'] — the self-sync ordering law depends on the flag (C01 fan-out)" % (locals_,))

raw = open(render).read()
# AC3's literal-domain ban guards the DERIVED leg against a baked prod domain.
# The two sanctioned override hosts legitimately contain spencerslab.com /
# scifi.farm (route truth, not an assumption), so the ban strips exactly those
# host strings first — a third hardcoded domain anywhere in the render still
# trips it, and the nine derived URLs are already pinned to the injected test
# domain by the exact-equality leg above.
stripped = raw
for oh in OVERRIDE_HOSTS.values():
    stripped = stripped.replace(oh, "<sanctioned-override-host>")
if "spencerslab.com" in stripped.lower():
    hits = [ln for ln in stripped.splitlines() if "spencerslab.com" in ln.lower()][:3]
    bad("t3: the render carries a literal spencerslab.com outside the two pinned override hosts — derived cluster URLs must be domain-injected from OVERRIDE_VIA_APPSET (AC3): %s" % hits)

blob2 = targets_of(render2)
if sorted(blob2.get("allowed_refs") or []) != ["refs/heads/main", "refs/heads/stage"]:
    bad("t3: --set allowedRefs[0/1] did not reach targets.json (allowed_refs: %r) — OQ7's one-values-edit widening is not plumbed" % (blob2.get("allowed_refs"),))
print("ok: t3 — hub entry == rendered Service %s on 8080; targets.json ships allowed_refs [refs/heads/main], the 11-category roster with rootApp/tokenKey/repo per contract and urls per the live-verified host set (dev/home fixed, nine derived), exactly one local flag, no un-sanctioned literal domain in the render, and allowedRefs overrides flow (AC3/OQ7)" % release)
PY
  then
    ok "t3 passed (AC3)"
  else
    fail "t3: the Service/targets.json contract is not satisfied (reason printed above)"
  fi
fi

# --- t4: trio entries + sentinel 1:1 + rename ripple docs (AC2/AC4) ----------------
if want t4; then
  if python3 - "$CHART/values.yaml" "$PROXY_VALS" "$CV" "$RUNBOOK" "$CHART/README.md" "$CHART/templates/secret-argocd-hook.yaml" "$CHART" "$CONT_README" <<'PY'
import os, re, sys, yaml

chart_values, proxy_vals_path, cv_path, runbook, chart_readme, hook_tpl, chart_dir, cont_readme = sys.argv[1:9]
SENT = "OVERRIDE_VIA_CUSTOM_VALUES"
old_fn = "github-" "webhook"  # retired filename, split: no old literal in this harness


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


def load(path):
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}


cv = load(chart_values)
ids = cv.get("bitwardenIds") or {}
want_ids = {"argocd-hook-secret": SENT, "argocd-hook-tokens": SENT}
if ids != want_ids:
    bad("t4: chart values bitwardenIds is %r, expected exactly %r (Hard rule: placeholders only, UUIDs live in custom-values; a third key would ship unresolvable)" % (ids, want_ids))

pv = load(proxy_vals_path)
entry = (pv.get("charts") or {}).get("argocd-hook")
if not isinstance(entry, dict):
    bad("t4: no charts.argocd-hook entry in %s — the appset-charts generator will never create the hub child app (AC4 trio leg 1)" % proxy_vals_path)
if entry.get("namespace") != "default":
    bad("t4: charts.argocd-hook.namespace is %r, expected default (hub services live in default, EXPLORE §5)" % entry.get("namespace"))
if str(entry.get("ServerSideApply")) != "true":
    bad("t4: charts.argocd-hook.ServerSideApply is %r, expected the string \"true\" (smtp-relay precedent shape, C02 task)" % entry.get("ServerSideApply"))
sub = ((pv.get("proxy") or {}).get("subdomains") or {}).get("argocd-hook")
if not isinstance(sub, dict):
    bad("t4: no proxy.subdomains.argocd-hook entry in %s — the public edge hop is missing (AC4 trio leg 2)" % proxy_vals_path)

pcv = load(cv_path)
block = pcv.get("argocd-hook")
if not isinstance(block, dict) or not isinstance(block.get("bitwardenIds"), dict):
    bad("t4: no top-level argocd-hook.bitwardenIds block in %s (smtp-relay precedent shape) — the sentinels would deploy unresolved (AC4)" % cv_path)
bw = block["bitwardenIds"]
if set(bw) != set(want_ids):
    bad("t4: custom-values argocd-hook.bitwardenIds keys %r != chart sentinels %r (1:1 rule)" % (sorted(bw), sorted(want_ids)))
for k in sorted(bw):
    if bw[k] != "OVERRIDE_NEEDED":
        bad("t4: %s.argocd-hook.bitwardenIds.%s is %r — until the owner fills the Bitwarden UUID post-merge the shipped line must read OVERRIDE_NEEDED (OQ5 ruling: sentinels merge as-is)" % (cv_path, k, bw[k]))
cv_text = open(cv_path).read()
if runbook not in cv_text:
    bad("t4: the custom-values sentinel block carries no pointer to %s — the crash-loop-until-filled posture must be findable from the sentinel (C02 task)" % runbook)

# --- C02-fix rename-ripple + R1 confirmation legs -------------------------------
tpl_text = open(hook_tpl).read()
if "secretKey: hook-secret" not in tpl_text:
    bad("t4: %s does not render the HMAC ES under secretKey hook-secret (R4: this string IS the flat filename the relay reads — the pairing leg is the source, the t2 leg is the render)" % hook_tpl)
if old_fn in tpl_text:
    bad("t4: %s still references the retired '%s' key name (R4 rename ripple)" % (hook_tpl, old_fn))
if 'index .Values "bitwardenIds" "argocd-hook-secret"' not in tpl_text:
    bad("t4: the hook-secret entry no longer sources the argocd-hook-secret bitwardenIds placeholder — secretKey renamed, uuid source must NOT move")
for tok, why in (("bitwarden-login", "login-item store"), ("password", "password property"),
                 ("verbatim", "keys-land-verbatim comment (the flat-filename contract)")):
    if tok not in tpl_text:
        bad("t4: %s lost the %s (%r) — AC1: the mapping and the filename-contract comment are otherwise byte-identical" % (hook_tpl, why, tok))

readme_text = open(chart_readme).read()
if "hook-secret" not in readme_text:
    bad("t4: the chart README surface list still misses hook-secret (C02-fix README task)")
if old_fn in readme_text:
    bad("t4: the chart README still names the retired '%s' file (R4 ripple incomplete)" % old_fn)
if "main-sync" not in readme_text:
    bad("t4: the chart README does not frame the caller as the main-sync hook job (C02-fix README task: caller framing follows the rulings)")

stale = []
for root, _dirs, files in os.walk(chart_dir):
    for fn in files:
        p = os.path.join(root, fn)
        try:
            if old_fn in open(p, errors="ignore").read():
                stale.append(os.path.relpath(p, chart_dir))
        except OSError:
            pass
if stale:
    bad("t4: the retired key name survives under %s: %s (AC3: 0 hits repo-wide under charts/argocd-hook/ after C02-fix)" % (chart_dir, stale))

vals_text = open(chart_values).read()
# C02-fix adds the WHY above the value: the live app sources still read
# GitHub (probe [P]) and app_matches byte-compares THAT, so the value stays
# and only a same-release annotation flip may change it. Designed-red pre-
# change: the shipped comment explains WHAT is matched, never the flip law.
m = re.search(r"(?:^[ \t]*#.*\n)+^[ \t]*trackedRepo:", vals_text, re.M)
if not m or not re.search(r"(?i)flip", m.group(0)):
    bad("t4: the trackedRepo comment block carries no flip warning (targetRevision/repoURL stay GitHub-sourced under ruling (c); flipping the value before the fleet annotations flip is the silent skipped-xN no-op trap — the comment is that guard rail)")
if "https://github.com/OwnYourIO/SpencersLab.git" not in vals_text:
    bad("t4: trackedRepo lost its GitHub URL — under ruling (c) it stays EXACTLY here (t3 pins the value; this is the R1 confirmation leg)")

# Cross-suite doc agreement (plan Commands: the two READMEs are ONE
# contract surface): the relay README and the chart README must tell the
# same R1/R4 story about the key file and the caller. R3's full header
# detail lives in the relay README (and is pinned there by
# tests/containers/argocd-hook-relay.sh t7); the chart README must at
# minimum not contradict it and must carry the renamed filename.
try:
    cont_text = open(cont_readme).read()
except OSError as ex:
    bad("t4: cannot read %s for the cross-suite agreement leg: %s" % (cont_readme, ex))
for tok in ("hook-secret", "main-sync"):
    if tok not in cont_text:
        bad("t4: doc agreement — the relay README (%s) lacks %r while this suite pins it in the chart README: R4/R1 framing must land on BOTH surfaces in the same wave (C02-fix depends on C01-fix for a reason)" % (cont_readme, tok))
if old_fn in cont_text:
    bad("t4: doc agreement — the relay README still names the retired '%s' file (the pair would render two different filenames onto one mounted directory)" % old_fn)
print("ok: t4 — chart sentinels exact, hub charts: entry well-formed, subdomain entry present, custom-values 1:1 OVERRIDE_NEEDED pairing with the runbook pointer; plus the C02-fix ripple: hook-secret template+README with zero retired-name hits in the chart tree, login-item mapping intact, the trackedRepo WHY-comment holding the GitHub URL per R1, and the relay README telling the same key-file/caller story (AC2/AC4/OQ5 + cross-suite parity)")
PY
  then
    ok "t4 passed (AC4)"
  else
    fail "t4: the trio/sentinel wiring contract is not satisfied (reason printed above)"
  fi
fi

# --- t5: diff scope — rename ripple only (C02-fix AC2/AC5) ------------------------
# The trio files moved in the ORIGINAL C02 (add-only then). Under C02-fix they
# must not move AT ALL: only chart-tree comment/rename lines (plus this wave's
# test surface and C04's workflow, which legitimately coexist uncommitted).
if want t5; then
  git rev-parse --verify --quiet "$BASE" >/dev/null ||
    fail "t5: CHUNK_BASE '$BASE' does not resolve (review passes the pre-chunk commit; default HEAD)"
  { git diff --name-only "$BASE" 2>/dev/null || true; git ls-files --others --exclude-standard; } |
    sort -u > "$WORK/changed.txt"
  if grep -Ev '^(charts/argocd-hook/|tests/[^/]+/argocd-hook-|tests/services/forgejo-main-sync\.sh$|\.forgejo/workflows/main-sync\.yaml$|\.agents/|\.pipeline/)' "$WORK/changed.txt" | grep -q .; then
    offenders=$(grep -Ev '^(charts/argocd-hook/|tests/[^/]+/argocd-hook-|tests/services/forgejo-main-sync\.sh$|\.forgejo/workflows/main-sync\.yaml$|\.agents/|\.pipeline/)' "$WORK/changed.txt" | head -20)
    fail "t5: C02-fix changed files outside the chart tree (AC5 — containers/ belongs to C01-fix; images/, custom-values/ and services/ must not move at all in a rename ripple): $offenders"
  fi
  if grep -Eq '^(charts/base/|services/[^/]+/templates/appset\.yaml$)' "$WORK/changed.txt"; then
    fail "t5: charts/base or a services appset template appears in the C02-fix change set (AC5 + OQ1: the gate files are off-limits)"
  fi
  if [ -n "$(git diff --name-only "$BASE" -- "$PROXY_VALS" "$CV" 2>/dev/null)" ]; then
    git diff -U3 "$BASE" -- "$PROXY_VALS" "$CV" 2>/dev/null | head -40 >&2
    fail "t5: $PROXY_VALS or $CV moved — C02-fix touches only the chart's 3 files (AC2: trio entries, custom-values 1:1 and the uuid block are UNCHANGED, not even a comment)"
  fi
  ok "t5: change set is the chart tree + test surface only; the trio and custom-values files carry zero hunks (C02-fix AC2/AC5)"
fi

# --- t6: crowdsec-only entry + standard security posture (AC6+AC7) --------------
if want t6; then
  if python3 - "$PROXY_VALS" <<'PY'
import re, sys, yaml

proxy_vals_path = sys.argv[1]


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


def load(path):
    lines = []
    with open(path) as f:
        for line in f:
            line = re.sub(r':[ \t]+&[A-Za-z0-9_-]+', ':', line)
            line = re.sub(r':[ \t]+\*[A-Za-z0-9_-]+', ': ANCHOR_REF', line)
            lines.append(line)
    return yaml.safe_load(''.join(lines)) or {}


CROWDSEC = "kube-system-crowdsec@kubernetescrd"
sub = ((load(proxy_vals_path).get("proxy") or {}).get("subdomains") or {}).get("argocd-hook") or {}
if sub.get("middlewares") != CROWDSEC:
    bad("t6: argocd-hook entry middlewares is %r, expected exactly %r (AC6 — forms/git crowdsec-only precedent)" % (sub.get("middlewares"), CROWDSEC))
ir = (sub.get("ingressRoute") or {}).get("middlewares")
if ir != [CROWDSEC]:
    bad("t6: argocd-hook ingressRoute.middlewares is %r, expected [%r] — both middleware keys must carry the crowdsec-only override (AC6)" % (ir, CROWDSEC))
dump = yaml.safe_dump(sub).lower()
for forbidden in ("oidc", "keycloak", "forward", "sso"):
    if forbidden in dump:
        bad("t6: the argocd-hook entry mentions %r — GitHub cannot do OIDC, the hub entry must stay SSO-free (AC6, OQ2 ruling)" % forbidden)
print("ok: t6: hub entry is crowdsec-only on both keys with no SSO/forward-auth residue (AC6)")
PY
  then
    ok "t6 entry legs passed (AC6)"
  else
    fail "t6: the hub subdomain entry is not crowdsec-only (reason printed above)"
  fi
  if [ -n "$RENDER" ]; then
    if python3 - "$RENDER" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]


def bad(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


workloads = [d for d in docs if d.get("kind") in ("Deployment", "StatefulSet", "DaemonSet")]
pod = ((workloads[0].get("spec") or {}).get("template") or {})
pod_spec = (pod.get("spec") or {})
c = (pod_spec.get("containers") or [{}])[0]
sc = c.get("securityContext") or {}
if sc.get("allowPrivilegeEscalation") is not False:
    bad("t6: allowPrivilegeEscalation is %r, expected false (AC7)" % sc.get("allowPrivilegeEscalation"))
drop = ((sc.get("capabilities") or {}).get("drop") or [])
if "ALL" not in drop:
    bad("t6: capabilities.drop is %r, expected to include ALL (AC7)" % drop)
if sc.get("readOnlyRootFilesystem") is not True:
    bad("t6: readOnlyRootFilesystem is %r, expected true — the relay writes nothing (C01 note; the pod must not run with a writable root)" % sc.get("readOnlyRootFilesystem"))
if pod_spec.get("automountServiceAccountToken") is not False:
    bad("t6: pod automountServiceAccountToken is %r, expected false — the relay talks to remote APIs with bearer tokens, it needs no cluster identity (AC7)" % (pod_spec.get("automountServiceAccountToken"),))
ann = ((pod.get("metadata") or {}).get("annotations") or {})
if ann.get("reloader.stakater.com/auto") != "true":
    bad("t6: pod annotation reloader.stakater.com/auto is %r, expected \"true\" — C03's token-rotation limitation depends on the reloader restarting the pod on mounted-secret changes" % ann.get("reloader.stakater.com/auto"))
if any(d.get("kind") == "PersistentVolumeClaim" for d in docs):
    bad("t6: the chart renders a PVC — the relay is stateless, no queue, no persistence (AC7 + C01 notes)")
if any(d.get("kind") == "Ingress" for d in docs):
    bad("t6: the chart renders its own Ingress — exposure is the hub subdomain entry ONLY (AC7); a chart ingress would be a second, unmanaged public path")
print("ok: t6: render carries drop-ALL/no-escalation/read-only-root/no-SA-automount, the reloader annotation, and neither a PVC nor an Ingress (AC7)")
PY
    then
      ok "t6 render legs passed (AC7)"
    else
      fail "t6: security posture violated (reason printed above)"
    fi
  fi
fi

rm -rf "$WORK"
printf 'PASS: argocd-hook wiring contract checks (%d ok)\n' "$checks"
