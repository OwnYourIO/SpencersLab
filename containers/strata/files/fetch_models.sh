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
#                          pseudo-families "orca" (gated manual pack) and
#                          "orn" (public GGUF-direct q36 legs) route to the
#                          steps below - neither is a setup.sh catalog name
#   HF_TOKEN               gated legs ONLY, via process env (R-d
#                          download-only: the hf-token secretKeyRef sits on
#                          this init and the token never reaches the serve path)
# Siblings baked beside it: hf_fetch.py (the downloader) and byte_pins.env
# (the shard byte literals it sources below).

set -eu
fail() { echo "model-fetch: $*" >&2; exit 1; }
# An interpreter that survives image replacement: PATH python3 first, then the
# terminal's bundled candidates (Strata's runtime ships its own python under
# /opt/strata/terminal, not a distro one). Echoes the path, rc 1 when none.
find_python3() {
  p=$(command -v python3 || true)
  [ -n "$p" ] && { echo "$p"; return 0; }
  for c in /opt/strata/terminal/bin/python3 /opt/strata/terminal/bin/python \
           /opt/strata/terminal/usr/bin/python3 /opt/strata/terminal/python/bin/python3; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}
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
# Session-file landing zone, kept from the q4 rung's retired --slot-save-path
# arm (the HIP engine compiled session files out, 2026-11-01 first boot). The
# dir is harmless and lets /models/strata stay the single version-free claim
# anchor for whatever the CUDA-trial feature becomes upstream. Created
# here, idempotently, because a missing directory surfaces as a save error
# at the worst possible moment (an operator trying to free the arena).
mkdir -p /models/strata/sessions
# /data/install stays the CLI's install-dir anchor, bound to the
# claim so discovery tools (models list --install-dir default)
# see what setup produced.
rm -rf /data/install
ln -sfn /models/strata /data/install
SRC=/models/strata/Strata
# Claim-checkout migration (cf-86 C09). The copy below is copy-ONCE, so a live
# claim keeps whatever tree it first copied: re-pinning the image would leave
# the node compiling last release's source while the serve profiles name this
# release's artifacts (the landmine RESEARCH R5 pulled out of our own shipped
# law). The marker is CONTENT-compared, not existence-tested, and its name
# carries the image version plus a carry counter — that comparison is what
# re-arms this step at the next bump.
# The sync enumerates the image tree and skips the CLAIM's data state — the
# data/ expert-profile, Strata-data/ (weights and packs), the strata-*.json run
# configs, .venv, engine/ and every .setup-*/.pack-*/.dl-* marker and .done
# file: the ~290 GB of provisioning state this step must survive; deleting
# $SRC would re-download and re-pack all of it. An allowlist of source dirs
# was tried first and went stale the moment upstream added a build input.
CHECKOUT_MARKER=/models/strata/.checkout-0.2.9-carry1
CHECKOUT_MARKER_ID=0.2.9-carry-1
if [ -d "$SRC" ] && [ "$( [ -f "$CHECKOUT_MARKER" ] && cat "$CHECKOUT_MARKER" )" != "$CHECKOUT_MARKER_ID" ]; then
  echo "model-fetch: the claim checkout predates the image - syncing sources (the engine recompiles below)"
  # Enumerate the IMAGE tree and sync everything except the claim's closed data
  # state. The previous hard-coded source allowlist went stale the day upstream
  # added a build input: v0.2.9's CMakeLists compiles tests/hip/gdn_stage_bench.cpp,
  # the allowlist left the claim's old tests/ in place, and cmake configure died
  # with "Cannot find source file" (2026-10-31 boot). Data state is the small,
  # contract-pinned set; the build tree is the part that legitimately moves.
  # Dotfiles (the claim's .venv, every .setup-*/.pack-*/.dl-*/.done marker) are
  # outside the glob by design - they are the idempotency state itself.
  for entry in /opt/strata/src/Strata/*; do
    b=${entry##*/}
    case "$b" in data|Strata-data|third_party|engine|build-hip) continue ;; esac
    rm -rf "$SRC/$b"
    cp -a "$entry" "$SRC"/
  done
  # third_party MERGES instead of replacing: setup.py unpacks its pinned
  # llama.cpp zip into it, so gguf-py and ggml are provisioning artifacts and
  # wiping the folder would destroy the pack step's own dependencies.
  cp -a /opt/strata/src/Strata/third_party "$SRC"/
  # The cache describes the pre-migration tree: it goes before the compile,
  # because a build over a stale cache is how a half-migrated engine could get
  # stamped as good.
  rm -rf "$SRC/build-hip"
  # The claim venv's bin/python is a symlink into the interpreter of whichever
  # image provisioned it; an image bump dangles it while the wheel-installed
  # tools beside it (cmake/ninja binaries) keep working — and setup.sh never
  # runs again on a provisioned claim (.setup-* markers skip it), so nothing
  # else rebuilds this venv. Re-point it when this image's interpreter matches
  # the venv's site-packages minor; a mismatch stays untouched and the guards
  # below fail loud instead of half-working (2026-10-31 first-boot finding).
  if [ -d "$SRC/.venv" ] && [ ! -x "$SRC/.venv/bin/python" ]; then
    imgpy=$(find_python3 || true)
    if [ -n "$imgpy" ] \
       && [ -d "$SRC/.venv/lib/python$("$imgpy" -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')/site-packages" ]; then
      ln -sfn "$imgpy" "$SRC/.venv/bin/python"
      ln -sfn "$imgpy" "$SRC/.venv/bin/python3"
      echo "model-fetch: claim venv python dangled at the previous image - re-pointed at $imgpy"
    fi
  fi
  # Metadata reads need an interpreter even where the venv stays broken: claim
  # venv first, image python3 as the fallback.
  PY="$SRC/.venv/bin/python"
  if [ ! -x "$PY" ]; then
    PY=$(find_python3) || fail "checkout migration: no usable python (claim venv broken and the image ships none)"
  fi
  # Nobody else recompiles a provisioned claim — the .setup-* markers make every
  # installed quant skip setup.sh — so the recompile lives here: the same
  # cmake/ninja pair and the same fixed HIP defs setup.py drives at this tag
  # (its Step 4; 10-20 minutes inside the init's 32 Gi), with the arch and the
  # ROCm root read back from the claim's own build metadata rather than guessed
  # here. Nothing compiled yet (a copied-but-never-provisioned claim) means
  # nothing to recompile: setup.sh compiles the synced tree on first
  # provisioning, and the marker below records that the sources already match.
  if [ -f "$SRC/engine/BUILD.json" ]; then
    # BUILD.json without the venv toolchain is a mixed claim state, not a fresh
    # copy; failing open here would leave an unpatched engine in place under a
    # written marker (C09 review r1), so this branch fails loud — the marker
    # only ever follows a green compile.
    [ -x "$SRC/.venv/bin/cmake" ] \
      || fail "checkout migration: $SRC/engine/BUILD.json promises a compiled engine but $SRC/.venv/bin/cmake is missing - fix the claim venv; the marker stays unwritten and the next boot re-enters"
    archs=$("$PY" -c 'import json,sys; print(";".join(json.load(open(sys.argv[1]))["archs"]))' "$SRC/engine/BUILD.json") \
      || fail "checkout migration: cannot read archs from $SRC/engine/BUILD.json"
    libdirs=$("$PY" -c 'import json,sys; print(";".join(json.load(open(sys.argv[1])).get("lib_dirs", [])))' "$SRC/engine/BUILD.json") \
      || fail "checkout migration: cannot read lib_dirs from $SRC/engine/BUILD.json"
    if [ -x /opt/rocm/bin/hipcc ] && [ -e /opt/rocm/lib/libhipblas.so ]; then
      rocm=/opt/rocm
    else
      rocm=$("$SRC/.venv/bin/rocm-sdk" path --root) \
        || fail "checkout migration: no ROCm to compile against (no system hipcc, and the venv SDK root is unreadable)"
    fi
    # setup.py's own compile environment (its build_engine_hip preamble): cmake
    # finds the HIP toolchain through these, not through anything baked here.
    export HIP_PLATFORM=amd HIP_COMPILER=clang HIP_RUNTIME=rocclr ROCM_PATH="$rocm" HIP_PATH="$rocm"
    LD_LIBRARY_PATH="$rocm/lib$(printf '%s' "$libdirs" | sed 's/^/:/; s/;/:/g')${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LD_LIBRARY_PATH
    PATH="$SRC/.venv/bin:$rocm/bin:$rocm/llvm/bin:$PATH"
    jobs=$(( $(nproc) / 2 ))
    if [ "$jobs" -lt 2 ]; then jobs=2; fi
    cmake -G Ninja -DCMAKE_MAKE_PROGRAM="$SRC/.venv/bin/ninja" -S "$SRC" -B "$SRC/build-hip" -DCMAKE_BUILD_TYPE=Release \
      -DSTRATA_ENABLE_HIP=ON -DSTRATA_ENABLE_CUDA=OFF -DSTRATA_BUILD_TESTS=OFF \
      -DSTRATA_PREFILL_MMQ=ON -DSTRATA_Q6K_EXPERTS=ON -DSTRATA_MMQ_KQUANTS=ON \
      "-DSTRATA_GGML_DIR=$SRC/third_party/llama.cpp" \
      "-DCMAKE_HIP_ARCHITECTURES=$archs" "-DCMAKE_HIP_COMPILER=$rocm/llvm/bin/clang++" \
      "-DCMAKE_HIP_COMPILER_ROCM_ROOT=$rocm" "-DCMAKE_PREFIX_PATH=$rocm${libdirs:+;$libdirs}" \
      "-DCMAKE_HIP_FLAGS=--rocm-path=$rocm --rocm-device-lib-path=$rocm/lib/llvm/amdgcn/bitcode" \
      || fail "checkout migration: cmake configure failed - the marker stays unwritten and the next boot re-enters"
    cmake --build "$SRC/build-hip" --target strata -j "$jobs" \
      || fail "checkout migration: engine recompile failed - the marker stays unwritten and the next boot re-enters"
    # The profiles name the version-free claim path, so the fresh binary lands
    # there. engine/BUILD.json keeps its old source hash, which makes the next
    # setup.sh recompile once on its own: self-healing, not a wedge.
    mkdir -p "$SRC/engine"
    cp -a "$SRC/build-hip/strata" "$SRC/engine/strata" \
      || fail "checkout migration: could not install the recompiled engine at $SRC/engine/strata"
  else
    echo "model-fetch: no compiled engine on this claim yet - setup.sh compiles the synced tree on first provisioning"
  fi
  # Written only now: a crash anywhere above re-enters this step instead of
  # leaving a half-built engine permanently marked as migrated.
  printf '%s\n' "$CHECKOUT_MARKER_ID" > "$CHECKOUT_MARKER"
  echo "model-fetch: claim checkout is at $CHECKOUT_MARKER_ID"
fi
if [ ! -d "$SRC" ]; then
  cp -a /opt/strata/src/Strata "$SRC"
  # A fresh claim starts from the image's patched checkout, so the migration
  # marker is simply recorded here (setup.sh compiles the engine during the
  # first provisioning; the next bump's marker mismatch re-fires the step
  # above).
  printf '%s\n' "$CHECKOUT_MARKER_ID" > "$CHECKOUT_MARKER"
else
  [ -f "$SRC/setup.sh" ] || fail "$SRC exists without setup.sh - refusing to overwrite"
fi
# setup.sh needs a python3 on PATH; this image ships only the
# terminal's bundled interpreter — find it, else self-diagnose.
if ! command -v python3 >/dev/null 2>&1; then
  p=$(find_python3 || true)
  if [ -n "$p" ]; then ln -sf "$p" /usr/local/bin/python3; fi
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
  # pseudo-families "orca" and "orn" are deliberately NOT catalog
  # names: they route the token to the manual pack and the
  # GGUF-direct legs below, neither of which has a setup.sh entry.
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
  if [ "$FAM" = orn ]; then
    # GGUF-direct q36 rung (cf-86 C09): Ornith-1.5-122B on the engine's
    # qwen35moe path. There is no setup.sh catalog entry for a third-party
    # repo, and unlike the orca route above there is nothing to build first —
    # q36's load() opens the GGUF and joins the shards itself — so this arm
    # only stages the three files under their ORIGINAL repo names, which is
    # exactly what the serve profile's --native pointer names.
    # The bytes are UNGATED (anonymous tree read plus a ranged resolve that
    # answered 206 with GGUF magic and no Bearer challenge, 2026-10-31), so
    # every leg rides hf_fetch's anon mode and no token enters this arm: the
    # DECISIONS 2026-10-31 "keep both modes" decision is what finally pays off
    # here. Completeness is .dl-ornith, guarded before the legs and written
    # only after all three landed on an exact byte match, so an interrupted
    # 79.7 GB set re-enters instead of serving missing weights. The legs are
    # spelled out instead of looped because the repo paths and the byte pins
    # are the audited literals — a loop over variables would hide which bytes
    # land in which file.
    if [ -f "/models/strata/.dl-ornith" ]; then
      echo "model-fetch: ornith shard set complete, skipping"
      continue
    fi
    echo "model-fetch: GGUF-direct anon legs for $tok ($SIZE unsloth Ornith-1.5-122B — no setup.sh catalog entry, no pack step)"
    [ -x "$SRC/.venv/bin/python" ] \
      || fail "ornith: $SRC/.venv missing - the q3 token must provision before ornith"
    tier=/models/strata/Strata-data/unsloth/Ornith-1.5-122B-GGUF/UD-Q4_K_XL
    mkdir -p "$tier"
    [ -s "$tier/Ornith-1.5-122B-UD-Q4_K_XL-00001-of-00003.gguf" ] \
      || { "$SRC/.venv/bin/python" /opt/strata/bin/hf_fetch.py anon "https://huggingface.co/unsloth/Ornith-1.5-122B-GGUF/resolve/main/UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00001-of-00003.gguf" /models/strata/Strata-data/unsloth/Ornith-1.5-122B-GGUF/UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00001-of-00003.gguf.part $ORNITH_UD_Q4_K_XL_SHARD1 \
           && mv /models/strata/Strata-data/unsloth/Ornith-1.5-122B-GGUF/UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00001-of-00003.gguf.part "$tier/Ornith-1.5-122B-UD-Q4_K_XL-00001-of-00003.gguf"; } \
      || fail "ornith: shard 1 leg failed (a .part is kept for the next boot's resume)"
    [ -s "$tier/Ornith-1.5-122B-UD-Q4_K_XL-00002-of-00003.gguf" ] \
      || { "$SRC/.venv/bin/python" /opt/strata/bin/hf_fetch.py anon "https://huggingface.co/unsloth/Ornith-1.5-122B-GGUF/resolve/main/UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00002-of-00003.gguf" /models/strata/Strata-data/unsloth/Ornith-1.5-122B-GGUF/UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00002-of-00003.gguf.part $ORNITH_UD_Q4_K_XL_SHARD2 \
           && mv /models/strata/Strata-data/unsloth/Ornith-1.5-122B-GGUF/UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00002-of-00003.gguf.part "$tier/Ornith-1.5-122B-UD-Q4_K_XL-00002-of-00003.gguf"; } \
      || fail "ornith: shard 2 leg failed (a .part is kept for the next boot's resume)"
    [ -s "$tier/Ornith-1.5-122B-UD-Q4_K_XL-00003-of-00003.gguf" ] \
      || { "$SRC/.venv/bin/python" /opt/strata/bin/hf_fetch.py anon "https://huggingface.co/unsloth/Ornith-1.5-122B-GGUF/resolve/main/UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00003-of-00003.gguf" /models/strata/Strata-data/unsloth/Ornith-1.5-122B-GGUF/UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00003-of-00003.gguf.part $ORNITH_UD_Q4_K_XL_SHARD3 \
           && mv /models/strata/Strata-data/unsloth/Ornith-1.5-122B-GGUF/UD-Q4_K_XL/Ornith-1.5-122B-UD-Q4_K_XL-00003-of-00003.gguf.part "$tier/Ornith-1.5-122B-UD-Q4_K_XL-00003-of-00003.gguf"; } \
      || fail "ornith: shard 3 leg failed (a .part is kept for the next boot's resume)"
    # The tokenizer the profile points at: setup's own step for a GGUF-direct
    # family builds ONLY this (its comment: "only the tokenizer: the engine
    # reads the GGUF itself"), from shard 1, with gguf-py out of the unpacked
    # llama.cpp source. Guarded on vocab.json so a re-entry does not redo it.
    if [ ! -f "$tier/tokenizer/vocab.json" ]; then
      ( cd "$SRC" && STRATA_GGUF_PY="$SRC/third_party/llama.cpp/gguf-py" .venv/bin/python \
          tools/strata_tokenizer.py --gguf "$tier/Ornith-1.5-122B-UD-Q4_K_XL-00001-of-00003.gguf" --out "$tier" ) \
        || fail "ornith: tokenizer build failed (nothing is marked, the next boot re-enters)"
    fi
    printf '%s\n' "ornith UD-Q4_K_XL 3-shard set staged against the byte_pins.env literals" > "/models/strata/.dl-ornith"
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
