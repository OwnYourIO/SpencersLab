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
{{/* llama-swap.firstMountPath returns the `path` of the first entry of an
advancedMounts per-container list, empty when absent - helm 3.16's dig cannot
descend through a slice, so list legs need this hop. */}}
{{- define "llama-swap.firstMountPath" -}}
{{- if and (kindIs "slice" .) (gt (len .) 0) (kindIs "map" (index . 0)) -}}
{{- dig "path" "" (index . 0) -}}
{{- end -}}
{{- end -}}

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
{{- $init := dig "controllers" "llama-swap" "initContainers" "autogen" dict $at -}}
{{- if not (kindIs "map" $init) -}}
  {{- fail "autogen: app-template initContainers.autogen is not a mapping - there is no args wiring this base.yaml guard can verify" -}}
{{- end -}}
{{- if hasKey $init "command" -}}
  {{- fail "autogen: the initContainer declares a command: - the degrade/generate logic lives in the image entrypoint (containers/llama-swap-autogen/entrypoint.sh), never in k8s yaml (shell-reintroduction tripwire)" -}}
{{- end -}}
{{- $args := $init.args -}}
{{- if not (kindIs "slice" $args) -}}
  {{- fail "autogen: no app-template initContainers.autogen args to render - the entrypoint flags would not exist to keep autogen.scanPaths and the base.yaml mount in sync" -}}
{{- end -}}
{{/*
  set on a shared dict is what persists the loop's findings: template
  variable assignments inside range die with the range scope.
*/}}
{{- $acc := dict "dirs" (list) "base" "" -}}
{{- range $i, $a := $args -}}
  {{- if eq (toString $a) "--scan-dir" -}}
    {{- if lt (add $i 1) (len $args) -}}
      {{- $_ := set $acc "dirs" (append $acc.dirs (toString (index $args (add $i 1)))) -}}
    {{- end -}}
  {{- else if eq (toString $a) "--base" -}}
    {{- if lt (add $i 1) (len $args) -}}
      {{- $_ := set $acc "base" (toString (index $args (add $i 1))) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if not $acc.dirs -}}
  {{- fail "autogen: the initContainer args carry no --scan-dir flag - autogen.scanPaths cannot be cross-checked" -}}
{{- end -}}
{{- if not $acc.base -}}
  {{- fail "autogen: the initContainer args carry no --base flag - the base.yaml ConfigMap mount cannot be cross-checked" -}}
{{- end -}}
{{/*
  Drift guard, both directions: the entrypoint quick-find (the --scan-dir
  set decides whether the generator runs at all) and the base.yaml scan
  roots MUST be the same set. Args-only dirs would find GGUFs the generator
  does not scan ("No models found" -> silent degrade over live models);
  scanPaths-only dirs would skip generation before the tool ever runs.
*/}}
{{- $want := join " " (sortAlpha $paths) -}}
{{- $got := join " " (sortAlpha $acc.dirs) -}}
{{- if ne $want $got -}}
  {{- fail (printf "autogen.scanPaths (%s) and the initContainer --scan-dir args (%s) disagree - edit both or neither" $want $got) -}}
{{- end -}}
{{- $mounts := dig "persistence" "autogen-base" "advancedMounts" "llama-swap" "autogen" list $at -}}
{{- $mountPath := trim (include "llama-swap.firstMountPath" $mounts) -}}
{{- if eq (toString $mountPath) "" -}}
  {{- fail "autogen: persistence.autogen-base carries no advancedMounts path for the autogen container - the --base arg cannot be verified against the ConfigMap mount" -}}
{{- end -}}
{{- $wantBase := printf "%s/base.yaml" (trimSuffix "/" (toString $mountPath)) -}}
{{- if ne $acc.base $wantBase -}}
  {{- fail (printf "autogen: the initContainer --base arg (%s) is not the base.yaml ConfigMap mount file (%s) - edit both or neither" $acc.base $wantBase) -}}
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
