#!/bin/sh
# llama-swap-autogen image entrypoint: generates the scanned config half and
# owns the degrade/fail-open logic, so the chart wires only image + args +
# mounts (CR4, DECISIONS 2026-10-24) - no shell rides in k8s yaml.
#
# Exit codes are the contract, not style (DECISIONS 2026-10-22 "Degrade
# path"): 0 after writing the degrade file, because crashlooping the pod over
# a scanned half that can only ADD models costs live consumers (Immich/HA/
# OpenWebUI) more than a missing half does. Nonzero exits ONLY on usage
# errors: a wiring bug must surface loudly instead of hiding behind the
# fail-open, so degrade-rc0 stays reserved for scan-empty / generate-fail.
set -u

BASE=""
OUT=""
HOME_ARG=""
SCAN_COUNT=0
# newline-joined list and space-joined display are two views of the same
# paths: the loop splits only on newlines (paths may contain spaces), the
# degrade reason must stay one line in the comment-only file.
SCAN_DIRS=""
SCAN_DISPLAY=""

usage() {
    printf 'usage: entrypoint.sh --scan-dir DIR [--scan-dir DIR ...] --base FILE --out FILE --home DIR\n' >&2
}

die_usage() {
    printf 'autogen: %s\n' "$1" >&2
    usage
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --scan-dir)
            [ $# -ge 2 ] || die_usage "--scan-dir requires a value"
            SCAN_DIRS="$SCAN_DIRS$2
"
            SCAN_DISPLAY="$SCAN_DISPLAY $2"
            SCAN_COUNT=$((SCAN_COUNT + 1))
            shift 2
            ;;
        --base)
            [ $# -ge 2 ] || die_usage "--base requires a value"
            [ -z "$BASE" ] || die_usage "--base given more than once"
            BASE="$2"
            shift 2
            ;;
        --out)
            [ $# -ge 2 ] || die_usage "--out requires a value"
            [ -z "$OUT" ] || die_usage "--out given more than once"
            OUT="$2"
            shift 2
            ;;
        --home)
            [ $# -ge 2 ] || die_usage "--home requires a value"
            [ -z "$HOME_ARG" ] || die_usage "--home given more than once"
            HOME_ARG="$2"
            shift 2
            ;;
        *)
            die_usage "unknown argument: $1"
            ;;
    esac
done

[ "$SCAN_COUNT" -gt 0 ] || die_usage "no --scan-dir given"
[ -n "$BASE" ] || die_usage "--base is required"
[ -n "$OUT" ] || die_usage "--out is required"
[ -n "$HOME_ARG" ] || die_usage "--home is required"

degrade() {
    printf '# llama-swap-config-autogen produced no scanned half (%s).\n' "$1"
    printf '# Written by the autogen initContainer degrade path; the\n'
    printf '# declared -config half loads untouched (fail-open, see the\n'
    printf '# charts/llama-swap/values.yaml autogen: block).\n'
}

# Quick-find before invoking anything: stock `generate` on an empty scan set
# exits nonzero ("No models found"), so short-circuit past it. -iname: the
# tool discovers *.gguf AND *.GGUF. One match is all the decision needs, so
# -print -quit exits find itself instead of letting `| head` SIGPIPE it.
found=""
old_ifs=$IFS
IFS='
'
for d in $SCAN_DIRS; do
    if [ -d "$d" ]; then
        found=$(find "$d" -iname '*.gguf' -print -quit 2>/dev/null)
        if [ -n "$found" ]; then
            break
        fi
    fi
done
IFS=$old_ifs

if [ -z "$found" ]; then
    echo "autogen: no GGUF files under$SCAN_DISPLAY - writing comment-only scanned half (fail-open)" >&2
    degrade "no GGUF files under scan roots:$SCAN_DISPLAY" > "$OUT"
    exit 0
fi

# --home is the writable cache contract made explicit (C03 review finding #1):
# read_gguf_metadata:true mkdir/writes ~/.cache/llama_swap_config_autogen
# unguarded, so HOME must land on the init-only emptyDir mount or the first
# GGUF on disk kills generate under readOnlyRootFilesystem.
HOME="$HOME_ARG"
export HOME

# generate's own stderr stays on the container log for triage (no redirect).
if ! llama-swap-config-autogen generate --config "$BASE" -o "$OUT"; then
    echo "autogen: generate failed - degrading to comment-only scanned half (fail-open; tool output above)" >&2
    degrade "generate exited nonzero; see the initContainer log above" > "$OUT"
fi
exit 0
