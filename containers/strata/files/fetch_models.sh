#!/bin/sh
# Strata weight staging for the gpu-ai strata pod — the model-fetch driver the
# chart's init container execs (charts/llama-swap strata controller,
# command: ["/opt/strata/bin/fetch_models.sh"], exec form on purpose: a
# not-yet-pushed image fails container START with zero script executed and the
# markers untouched, which is what makes the chart+image one-commit landing
# self-healing). Lifted verbatim out of values.yaml by cf-86 C07 so the logic
# is build-verified (sh -n + the pins/downloader trio in the same verify RUN)
# instead of 330 unparseable YAML lines; the chart keeps intent + the env
# contract only.
#
# Env contract (set by the chart init container, scalars only):
#   STRATA_QUANTS          comma-separated quant tokens, default "q3"
#   STRATA_MODEL_<TOK>     [family/]model mapping for non-q3 tokens; the
#                          pseudo-family "orca" routes to the manual pack
#                          below (no setup.sh catalog entry exists)
#   HF_TOKEN               gated legs ONLY, via process env (R-d
#                          download-only: the hf-token secretKeyRef sits on
#                          this init and the token never reaches the serve path)
# Siblings baked beside it: hf_fetch.py (the downloader) and byte_pins.env
# (the shard byte literals it sources below).

set -eu
fail() { echo "model-fetch: $*" >&2; exit 1; }
# The byte literals every download leg verifies against are a baked sibling,
# not a copy of them here: one home, sourced. Fail before any work if the
# image predates the bake — an unbound pin would surface as a cryptic shell
# error minutes later, mid-download.
[ -f /opt/strata/bin/byte_pins.env ] \
  || fail "image carries no /opt/strata/bin/byte_pins.env - containers/strata must be rebuilt (C07 contract)"
. /opt/strata/bin/byte_pins.env
[ -f /opt/strata/src/Strata/setup.sh ] \
  || fail "image carries no source checkout - containers/strata must be rebuilt (strata-src stage, 2026-10-29 contract)"
mkdir -p /models/strata
# Session-file landing zone for the Q4 rung's --slot-save-path
# (strata-q4.json): same claim as the weights, so a saved
# conversation outlives a ttl unload AND a pod Recreate. Created
# here, idempotently, because the engine writes only on demand
# and a missing directory surfaces as a save error at the worst
# possible moment (an operator trying to free the arena). The
# engine's own --session-min-free-mib 4096 default guards the
# claim's free space; the disk gate for this rung's ~4.7 GiB per
# 262k conversation file is a human on-target check.
mkdir -p /models/strata/sessions
# /data/install stays the CLI's install-dir anchor, bound to the
# claim so discovery tools (models list --install-dir default)
# see what setup produced.
rm -rf /data/install
ln -sfn /models/strata /data/install
SRC=/models/strata/Strata
if [ ! -d "$SRC" ]; then
  cp -a /opt/strata/src/Strata "$SRC"
else
  [ -f "$SRC/setup.sh" ] || fail "$SRC exists without setup.sh - refusing to overwrite"
fi
# setup.sh needs a python3 on PATH; this image ships only the
# terminal's bundled interpreter — find it, else self-diagnose.
if ! command -v python3 >/dev/null 2>&1; then
  for c in /opt/strata/terminal/bin/python3 /opt/strata/terminal/bin/python \
           /opt/strata/terminal/usr/bin/python3 /opt/strata/terminal/python/bin/python3; do
    if [ -x "$c" ]; then ln -sf "$c" /usr/local/bin/python3; break; fi
  done
fi
command -v python3 >/dev/null 2>&1 \
  || fail "no python3 to drive setup.sh; terminal layout: $(find /opt/strata/terminal -maxdepth 3 -name 'python*' 2>/dev/null | tr '\n' ' ')"
# setup.sh Step 4 compiles the AMD engine for the checkout.
# git + a C++ compiler are BAKED into the image (2026-10-29
# owner ruling: runtime apt in an init container = pod-start
# mirror dependency + non-reproducible layer); the Dockerfile
# verify step pins the same two commands, so a missing tool
# fails the build, not the boot.
command -v git >/dev/null 2>&1 \
  && command -v c++ >/dev/null 2>&1 \
  || fail "image lacks git/c++ for the engine compile - containers/strata must be rebuilt (build-deps RUN, 2026-10-29 contract)"
# Manual pack for the gated orcarouter Uncensored IQ4_XS trio (cf-86 C02's
# rung, shifted up the orcarouter quant ladder from IQ3_XXS by the U9.2 owner
# ruling — same frozen arena id, no new provisioning token). The catalog gate
# has two proofs at v0.2.8: setup.py carries no orca family (docs/ORCA.md:
# "OrcaRouter is not an installer menu entry, and there is no --family orca"),
# and setup.py has ZERO download-auth support (no HF_TOKEN/Authorization/Bearer
# path in the whole 640 KB installer) — so even a catalog family could never
# fetch a gated repo, and branch B is forced. There is no Strata doc page for
# this rung (ORCA.md validated IQ3_XXS, ORCA_Q4_K_S.md the Q4_K_S trio), which
# makes it feasible-with-prep, not validated: plain IQ4_XS experts are already
# kernel-supported on the q38 path — unsloth's UD-IQ4_XS is catalog-served on
# AMD since engine 0.1.31/0.1.32 — so zero build flags and zero kernel gap
# (RESEARCH R4). The recipe is ORCA.md's, tier-swapped: stage the three shards
# under their original names at the repo root (iq_pack reads the split set
# from one directory), pack with --compat-bf16 — the same publisher/quantizer
# pipeline whose IQ3_XXS shards provably compressed the projections Strata's
# kernels read as BF16 — and output to the tier-named pack dir. If the first
# IQ4_XS provisioning's iq_pack log shows the Q4 tier shipped BF16 projections
# after all, the fix is a one-line iq_pack flag flip + pack rebuild at the
# human on-target gate, decided there, not pre-trimmed here. The BYTES are
# gated (resolve/main 401 + Bearer challenge measured 2026-10-30) while the
# tree metadata is public, so this fetch is the one hf-token Secret consumer
# the R-d ruling sanctions, strictly DOWNLOAD-ONLY: no token reaches the
# strata container, the inner config, or any profile (C-A keyless serve
# posture).
orca_pack() {
  # $1 = quant tier (IQ4_XS, from STRATA_MODEL_ORCA). Same Strata-data
  # staging shape as the catalog tiers, -orca suffix because these are
  # different bytes than the catalog tier of the same name.
  tier=$1
  tierl=$(printf '%s' "$tier" | tr 'A-Z' 'a-z')
  dir=/models/strata/Strata-data/models/$tier-orca
  pack=/models/strata/Strata-data/packs/orca-$tierl
  stem=Qwen3.8-Flash-Next-Uncensored-$tier
  s1=$dir/$stem-00001-of-00003.gguf
  # The IQ4_XS tier splits into three shards at the flat repo root (live
  # tree read 2026-10-31); ALL of them get staged — iq_pack reads the
  # whole split set from the one directory. ORCA.md's PLE-rides-inside-
  # shard-1 pattern is carried to the profile side, with the 3-shard
  # placement confirmed at the on-target serve --plan gate.
  s2=$dir/$stem-00002-of-00003.gguf
  s3=$dir/$stem-00003-of-00003.gguf
  # Guards before any byte moves (C01 review law): never start
  # 97.47 GB of downloads for a pack this init cannot build.
  [ -x "$SRC/.venv/bin/python" ] \
    || fail "orca pack: $SRC/.venv missing - the q3 token must provision before orca"
  ggufpy=$SRC/third_party/llama.cpp/gguf-py
  [ -d "$ggufpy" ] \
    || fail "orca pack: no gguf-py at $ggufpy - setup unpacks the pinned llama.cpp source during provisioning"
  mkdir -p "$dir"
  # Gated mode of the baked downloader: /opt/strata/bin/hf_fetch.py
  # (stdlib urllib — the bake+verify RUN proves this image ships no curl).
  # The hop-walk law and its 2026-10-30 measurements live with the code that
  # walks the hops; here the token only ever sits in this function's env.
  orca_dl() {
    [ -s "$2" ] && { echo "model-fetch: $(basename "$2") already staged"; return 0; }
    "$SRC/.venv/bin/python" /opt/strata/bin/hf_fetch.py gated "$1" "$2.part" "$3" \
      || fail "orca pack: download failed for $1 (partial kept as $2.part for a resume)"
    mv "$2.part" "$2" || fail "orca pack: rename failed for $2"
  }
  # Byte pins are the HF tree-API literals the pack contract is built on;
  # the orca IQ4_XS trio in byte_pins.env sums to 97473155200 = RESEARCH
  # R4's 97.47 GB. The downloader renames a .part only on an exact match.
  orca_dl "https://huggingface.co/orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF/resolve/main/$stem-00001-of-00003.gguf" "$s1" $ORCA_IQ4_XS_SHARD1
  orca_dl "https://huggingface.co/orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF/resolve/main/$stem-00002-of-00003.gguf" "$s2" $ORCA_IQ4_XS_SHARD2
  orca_dl "https://huggingface.co/orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF/resolve/main/$stem-00003-of-00003.gguf" "$s3" $ORCA_IQ4_XS_SHARD3
  # setup's own completeness guard (native_experts.txt is
  # written last by iq_pack): a crash between pack build and the
  # marker re-enters here instead of serving a partial pack.
  if [ ! -f "$pack/native_experts.txt" ] || [ ! -f "$pack/tokenizer/vocab.json" ]; then
    # --compat-bf16 is ORCA.md's answer to THIS quantizer: it
    # expands only the hyper-connection/small-attention/PLE
    # projections orcarouter compressed but Strata reads as BF16;
    # experts, native attention, embeddings and the PLE table
    # stay untouched (and the table stays on disk).
    ( cd "$SRC" && STRATA_GGUF_PY="$ggufpy" .venv/bin/python tools/iq_pack.py --gguf "$s1" --out "$pack" --compat-bf16 ) \
      || fail "orca pack: iq_pack failed (nothing is marked, the next boot resumes)"
  fi
}
IFS=,
for tok in ${STRATA_QUANTS:-q3}; do
  [ -n "$tok" ] || continue
  TOK=$(printf '%s' "$tok" | tr 'a-z' 'A-Z')
  FAM=qwen
  case "$TOK" in
    Q3) SIZE=IQ3_S ;;
    *)  SIZE=$(printenv "STRATA_MODEL_$TOK" || true) ;;
  esac
  # STRATA_MODEL_Qx may name another catalog family as
  # "family/model" (e.g. unsloth/UD-Q4_K_XL — the q4/q5 the
  # qwen family does not carry); a bare name stays qwen. The
  # pseudo-family "orca" is deliberately NOT a catalog name: it
  # routes the token to the manual pack above.
  case "$SIZE" in
    */*) FAM=${SIZE%%/*}; SIZE=${SIZE#*/} ;;
  esac
  if [ -z "$SIZE" ]; then
    echo "model-fetch: no model id mapped for quant '$tok' - set env STRATA_MODEL_$TOK=[family/]model (catalog: ./setup.sh --help in $SRC)" >&2
    exit 1
  fi
  MARK="/models/strata/.setup-$TOK"
  if [ -f "$MARK" ]; then
    echo "model-fetch: $tok already set up, skipping"
    continue
  fi
  if [ "$FAM" = orca ]; then
    # The 97.47 GB gated pack carries its OWN completeness
    # marker at the chunk-frozen path: touched only after the
    # staged shards AND the pack built (orca_pack fail-exits on
    # any partial), so an interrupted pack re-enters the step
    # instead of being marked done — a marker written early
    # would make a partial pack permanent and the arena would
    # serve missing weights. Re-entry is cheap: the -s skip and
    # the native_experts.txt guard short-circuit everything but
    # a genuinely missing byte.
    OMARK="/models/strata/.pack-orca"
    if [ -f "$OMARK" ]; then
      echo "model-fetch: orca pack complete, skipping"
      continue
    fi
    echo "model-fetch: gated manual pack for $tok ($SIZE orcarouter Uncensored — no setup.sh catalog entry)"
    orca_pack "$SIZE"
    touch "$OMARK"
    continue
  fi
  echo "model-fetch: setup.sh for $tok as $FAM/$SIZE (downloads start here)"
  # --backend hip is mandatory, not a preference: setup.sh probes
  # NVIDIA by default and hard-stops "no NVIDIA GPU found" on this
  # AMD node (deploy 2026-10-29); SOURCE_INSTALL.md AMD section
  # names the explicit selector. The init container therefore
  # mounts /dev/kfd + /dev/dri (the chart's advancedMounts)
  # — the HIP probe must see the card, or it fails the same lie
  # in the other direction.
  ( cd "$SRC" && ./setup.sh --backend hip --family "$FAM" --model "$SIZE" --context 262144 --vision no --no-start --yes )
  touch "$MARK"
done
ls -la "$SRC"/strata-*.json 2>/dev/null \
  || echo "model-fetch: WARNING no strata-*.json run config found - inspect $SRC before serving"
echo "model-fetch: quants [${STRATA_QUANTS:-q3}] provisioned via checkout on the claim"
