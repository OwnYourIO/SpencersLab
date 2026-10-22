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
