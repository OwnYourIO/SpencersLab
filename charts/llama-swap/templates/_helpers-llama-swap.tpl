{{/*
llama-swap.declaredConfig renders the llama-swap config.yaml from the compact
roster schema in .Values.config: config.models entries are composed into the
llama-swap surface (see llama-swap.modelCmd); every other config key passes
through untouched. filterPresets is a chart-values concept only — it must not
appear in the rendered config (llama-swap has no such key).

macros/matrix/hooks staying top-level here is load-bearing, not style: the
v262 -config-dir merge treats matrix (and its vars/sets children) as identity
maps, so any of these keys reaching the generated half a second time is a hard
config-load error (DECISIONS 2026-10-22 "two-file layout").
*/}}
{{- define "llama-swap.declaredConfig" -}}
{{- $cfg := deepCopy .Values.config -}}
{{- $presets := $cfg.filterPresets | default dict -}}
{{- $_ := unset $cfg "filterPresets" -}}
{{- $models := dict -}}
{{- range $id, $m := $cfg.models -}}
  {{- $cmd := include "llama-swap.modelCmd" (dict "id" $id "model" $m) -}}
  {{- $out := deepCopy $m -}}
  {{- range (list "hf" "draft" "spec" "use" "flags" "disabled") -}}
    {{- $_ := unset $out . -}}
  {{- end -}}
  {{- $_ := set $out "cmd" $cmd -}}
  {{- if kindIs "string" $out.filters -}}
    {{- if not (hasKey $presets $out.filters) -}}
      {{- fail (printf "model %s: filters references unknown filterPresets entry %s" $id $out.filters) -}}
    {{- end -}}
    {{- $_ := set $out "filters" (deepCopy (get $presets $out.filters)) -}}
  {{- end -}}
  {{- if not (hasKey $out "proxy") -}}
    {{- /* ${PORT} cmds always proxy to the pod-local port llama-swap assigned */ -}}
    {{- $_ := set $out "proxy" "http://localhost:${PORT}" -}}
  {{- end -}}
  {{- $_ := set $models $id $out -}}
{{- end -}}
{{- $_ := set $cfg "models" $models -}}
{{- toYaml $cfg -}}
{{- end -}}

{{/*
llama-swap.modelCmd composes one model's cmd string. Precedence:
disabled > raw cmd (escape hatch) > hf-composition.

The `use` macros are emitted as `${name}` references, never pre-expanded:
llama-swap expands them at load, and the rendered token stream is the
consumer-visible flag contract (tests/golden pin it as a multiset).
Composition keeps macros before `flags` so rightmost-wins collisions
resolve like the hand-written cmd they replace (e.g. gpu's -ub 1024
after ${...}).

The disabled branch renders the lab's fail-fast shape: the model exits 1
with a logged reason instead of loading (a routable "unavailable" beats a
404, and avoids the VRAM-exhaustion node freezes of 2026-10-18).
Trailing newlines reproduce the `cmd: |` block-scalar values the golden
captures — the disabled echo strings are compared byte-exact.
*/}}
{{- define "llama-swap.modelCmd" -}}
{{- $m := .model -}}
{{- if hasKey $m "disabled" -}}
{{- printf "/bin/sh -c \"echo '%s %s' >&2; exit 1\"\n" .id (get $m "disabled") -}}
{{- else if hasKey $m "cmd" -}}
{{- get $m "cmd" -}}
{{- else -}}
{{- $lines := list "${server-cmd}" -}}
{{- with $m.hf -}}
{{- $lines = append $lines (printf "-hf %s" .) -}}
{{- end -}}
{{- with $m.draft -}}
{{- $lines = append $lines (printf "-hfd %s" .) -}}
{{- end -}}
{{- with $m.use -}}
{{- range . -}}
{{- $lines = append $lines (printf "${%s}" .) -}}
{{- end -}}
{{- end -}}
{{- with $m.spec -}}
{{- $spec := printf "--spec-type %v --spec-draft-n-max %v" .type .draft_n_max -}}
{{- if hasKey . "draft_p_min" -}}
{{- $spec = printf "%s --spec-draft-p-min %v" $spec .draft_p_min -}}
{{- end -}}
{{- $lines = append $lines $spec -}}
{{- end -}}
{{- with $m.flags -}}
{{- $flags := trim . -}}
{{- if ne $flags "" -}}
{{- $lines = append $lines $flags -}}
{{- end -}}
{{- end -}}
{{- printf "%s\n" ($lines | join "\n") -}}
{{- end -}}
{{- end -}}

{{/*
llama-swap.autogenBase renders base.yaml, the input contract for the pinned
llama-swap-config-autogen generator (containers/llama-swap-autogen; key
spellings verified against archive commit c7357e68, not guessed).

Scanned-half ONLY, by construction. Two merge-safety rules drive this
(v262 internal/config/merge.go + generator.py generate_full_config):
 - the generator re-emits every *unknown* top-level base.yaml key verbatim
   into 10-scanned.yaml, so matrix/hooks/groups (identity-map children -
   duplicate child keys across config files are a hard load error) and any
   top-level scalar that could differ from the declared half must never
   appear here. The four generator-owned keys (vram_estimation,
   read_gguf_metadata, model_labels, path_prefix_map) are stripped by the
   tool itself, so they are safe to declare.
 - generated model IDs are `<dir>:<QUANT>` (lowercased scan-relative dir +
   filename quant token), so declared model IDs stay colon-free: the two
   halves' `models` identity maps can never collide across -config/
   -config-dir. This invariant is pinned by test_autogen_wiring.

`macros:` carries the declared-half macros by reference (deep-copy of the
same values source - the superset-slice test requires byte-equality under
shared names) plus the two generator contract macros: `binary` (the cmd
template hardwires ${binary}) and `default-params` - the tool falls back to
a synthetic model_pattern macro of exactly that name for any scanned model
matching no model_patterns entry (generator.py
get_model_pattern_config), and an undefined macro reference fails the
llama-swap config load, so it MUST be defined here.
*/}}
{{- define "llama-swap.autogenBase" -}}
{{- $a := .Values.autogen -}}
{{- $paths := $a.scanPaths | default list -}}
{{- if not $a.binary -}}
  {{- fail "autogen.binary missing - the generator's fixed cmd template needs ${binary}" -}}
{{- end -}}
{{- if not $a.defaultParams -}}
  {{- fail "autogen.defaultParams missing - scanned models fall back to ${default-params} and llama-swap fails to load undefined macros" -}}
{{- end -}}
{{/* dig rejects chartutil.Values at the root - drop to the plain sub-map. */}}
{{- $at := index .Values "app-template" | default dict -}}
{{- $cmd := dig "controllers" "llama-swap" "initContainers" "autogen" "command" nil $at -}}
{{- if not (kindIs "slice" $cmd) -}}
  {{- fail "autogen: no app-template initContainers.autogen command to render - the degrade quick-find would not exist to keep in sync with autogen.scanPaths" -}}
{{- end -}}
{{- $joined := join " " $cmd -}}
{{- if not (contains `SCAN_DIRS="` $joined) -}}
  {{- fail "autogen: the init script defines no SCAN_DIRS=\"...\" assignment - templates/configmap-autogen-base.yaml cannot verify it against autogen.scanPaths" -}}
{{- end -}}
{{- $dirsRaw := index (splitList "\"" (index (splitList `SCAN_DIRS="` $joined) 1)) 0 -}}
{{/*
  Drift guard, both directions: the quick-find (decides whether the generator
  runs at all) and the base.yaml scan roots MUST be the same set. Script-only
  paths would find GGUFs the generator does not scan ("No models found" ->
  silent degrade over live models); values-only paths would skip generation
  before the tool ever runs.
*/}}
{{- $want := join " " (sortAlpha $paths) -}}
{{- $got := join " " (sortAlpha (splitList " " (trim $dirsRaw))) -}}
{{- if ne $want $got -}}
  {{- fail (printf "autogen.scanPaths (%s) and the initContainer SCAN_DIRS (%s) disagree - edit both or neither" $want $got) -}}
{{- end -}}
{{- $macros := deepCopy (.Values.config.macros | default dict) -}}
{{- $_ := set $macros "binary" $a.binary -}}
{{- $_ := set $macros "default-params" $a.defaultParams -}}
{{- $base := dict -}}
{{- $_ := set $base "models" $paths -}}
{{- $_ := set $base "macros" $macros -}}
{{- $_ := set $base "read_gguf_metadata" true -}}
{{- $_ := set $base "vram_estimation" false -}}
{{- toYaml $base -}}
{{- end -}}
