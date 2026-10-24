{{/*
llama-swap.declaredConfig renders the llama-swap config.yaml from the compact
roster schema in .Values.config (CA2, plan REPLAN CR1; CR5 derivation):

- config.families is the FULL catalog: every family x rung pair expands into
  one model entry. Field merge layering is family < rung < raw config.models
  (deep merge; lists replace wholesale, same semantics as Helm's own value
  layering - CA2 note "per-rung use/flags overrides are full replacements").
  The rendered ID is rung.id | "<family>-<quant>"; a derived ID seen twice
  fails the render (catalog identity must be machine-unique or -config-dir
  merges silently lose entries).
- CR5 resolution order is PINNED per rung: compose the effective -hf ref
  (llama-swap.deriveHf), derive name/description from THAT rung-level ref
  (llama-swap.deriveDisplay), and only then merge raw config.models over the
  top - so a models-layer hf/name/description override wins WITHOUT ever
  re-deriving display text (DECISIONS 2026-10-24 CA3 precedence ruling).
  A family-expanded rung that ends up with no hf, no cmd and no disabled
  fails the render naming the rung: a catalog entry that cannot resolve a
  download is always an authoring mistake, never a routable no-op model
  (loud-offender rule, G1 precedent).
- enablement: a rung renders live only when family- or rung-level `enabled`
  wins the merge as true (an explicit rung enabled:false beats an enabled
  family); a not-enabled rung takes the deviation-1 fail-fast echo path with
  the catalog-default "not enabled on this cluster" message unless a
  `disabled:` message (chart, family, rung or models layer) supplies one -
  that is how per-cluster legacy echo strings stay byte-exact.
- config.models keeps its C02 role as the per-ID override + raw-cmd escape
  hatch layer, merged OVER the expansion; models-only IDs render as before
  (CR1.5). Precedence disabled > cmd > hf-composition stays in
  llama-swap.modelCmd, untouched.
- families/filterPresets/tagCultures are chart-values concepts: stripped,
  never rendered (llama-swap has no such key), as are the per-rung CR5
  vocabulary keys (llama-swap.deriveHf/deriveDisplay read them).

macros/matrix/hooks staying top-level here is load-bearing, not style: the
v262 -config-dir merge treats matrix (and its vars/sets children) as identity
maps, so any of these keys reaching the generated half a second time is a hard
config-load error (DECISIONS 2026-10-22 "two-file layout").
*/}}
{{- define "llama-swap.declaredConfig" -}}
{{- $cfg := deepCopy .Values.config -}}
{{- $presets := $cfg.filterPresets | default dict -}}
{{- $_ := unset $cfg "filterPresets" -}}
{{- $cultures := $cfg.tagCultures | default dict -}}
{{- $_ := unset $cfg "tagCultures" -}}
{{- $families := $cfg.families | default dict -}}
{{- $_ := unset $cfg "families" -}}
{{- $raw := $cfg.models | default dict -}}
{{- $_ := unset $cfg "models" -}}
{{- $models := dict -}}
{{- $derived := dict -}}
{{- range $fam, $spec := $families -}}
  {{- $familyFields := omit (deepCopy ($spec | default dict)) "quants" -}}
  {{- range $quant, $rung := (get ($spec | default dict) "quants") | default dict -}}
    {{- $m := mergeOverwrite (deepCopy $familyFields) (deepCopy ($rung | default dict)) -}}
    {{- $id := default (printf "%s-%s" $fam $quant) (get $m "id") -}}
    {{- if hasKey $derived $id -}}
      {{- fail (printf "CA2 family expansion: duplicate model id %s - derived from both %s and %s-%s; every family/rung pair must yield a unique rendered id (id: overrides included)" $id (get $derived $id) $fam $quant) -}}
    {{- end -}}
    {{- $_ := set $derived $id (printf "%s-%s" $fam $quant) -}}
    {{- $hf := trim (include "llama-swap.deriveHf" (dict "model" $m "quant" $quant "cultures" $cultures)) -}}
    {{- if $hf -}}
      {{- $_ := set $m "hf" $hf -}}
      {{- $_ := include "llama-swap.deriveDisplay" (dict "model" $m "ref" $hf "id" $id) -}}
    {{- end -}}
    {{- if hasKey $raw $id -}}
      {{- $m = mergeOverwrite $m (deepCopy (get $raw $id)) -}}
    {{- end -}}
    {{- $enabled := get $m "enabled" -}}
    {{- $_ := unset $m "enabled" -}}
    {{- $_ := unset $m "id" -}}
    {{- if and (not $enabled) (not (hasKey $m "disabled")) -}}
      {{- $_ := set $m "disabled" "is not enabled on this cluster - see the chart catalog" -}}
    {{- end -}}
    {{- $_ := set $models $id $m -}}
  {{- end -}}
{{- end -}}
{{- range $id, $m := $raw -}}
  {{- if not (hasKey $models $id) -}}
    {{- $_ := set $models $id $m -}}
  {{- end -}}
{{- end -}}
{{- $out := dict -}}
{{- range $id, $m := $models -}}
  {{- if and (hasKey $derived $id) (not (hasKey $m "cmd")) (not (hasKey $m "hf")) (not (hasKey $m "disabled")) -}}
    {{- fail (printf "CR5 catalog: model %s (family rung %s) resolves no -hf ref and declares neither cmd nor disabled - give it an hf literal, a composable repo/hfRepo + tag/tagCulture, a raw cmd, or a disabled reason" $id (get $derived $id)) -}}
  {{- end -}}
  {{- $cmd := include "llama-swap.modelCmd" (dict "id" $id "model" $m) -}}
  {{- $e := deepCopy $m -}}
  {{- range (list "hf" "draft" "spec" "use" "flags" "disabled" "enabled" "id" "hfRepo" "tagCulture" "repo" "tag" "dispName" "disp" "suffix" "descBase" "descTail" "size") -}}
    {{- $_ := unset $e . -}}
  {{- end -}}
  {{- $_ := set $e "cmd" $cmd -}}
  {{- if kindIs "string" $e.filters -}}
    {{- if not (hasKey $presets $e.filters) -}}
      {{- fail (printf "model %s: filters references unknown filterPresets entry %s" $id $e.filters) -}}
    {{- end -}}
    {{- $_ := set $e "filters" (deepCopy (get $presets $e.filters)) -}}
  {{- end -}}
  {{- if not (hasKey $e "proxy") -}}
    {{- /* ${PORT} cmds always proxy to the pod-local port llama-swap assigned */ -}}
    {{- $_ := set $e "proxy" "http://localhost:${PORT}" -}}
  {{- end -}}
  {{- $_ := set $out $id $e -}}
{{- end -}}
{{- $_ := set $cfg "models" $out -}}
{{- toYaml $cfg -}}
{{- end -}}

{{/*
llama-swap.deriveHf resolves one rung's effective -hf ref (CR5 grammar,
pinned before display derivation): rung `hf` literal >
{repo | hfRepo} ":" {tag | config.tagCultures[tagCulture][quant-key]}.
The culture maps are chart VALUES data, never a regex: irregular rungs
stay honest per-rung tag:/hf: exceptions. Input: dict model=merged rung map,
quant=rung key, cultures=config.tagCultures. Empty output = unresolvable;
the caller owns the loud-offender fail vs raw-cmd/disabled escape.
*/}}
{{- define "llama-swap.deriveHf" -}}
{{- $m := .model -}}
{{- if get $m "hf" -}}
{{- get $m "hf" -}}
{{- else -}}
{{- $repo := get $m "repo" | default (get $m "hfRepo") -}}
{{- $tag := get $m "tag" -}}
{{- $culture := get .cultures (get $m "tagCulture" | default "") -}}
{{- if kindIs "map" $culture -}}
{{- $tag = $tag | default (get $culture .quant) -}}
{{- end -}}
{{- if and $repo $tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
llama-swap.deriveDisplay composes picker text over the merged rung map
(in-place; derive-if-absent, so an explicit name/description at family,
rung or models layer always beats it). Only rungs with a resolved -hf ref
are decorated: raw-cmd rungs (whisper) and unresolvable ones (fail-rendered
upstream) keep explicit text by construction.
  NAME  {disp | dispName | id} ({TAG}{, MTP iff draft or spec present})
        { - suffix}
  DESC  {descBase | NAME-part}, {TAG} quant  -  or "(no quant)" for
        BF16/F16 - then the descTail appended VERBATIM (family default, rung
        override; its leading punctuation is data, so tails stay byte-exact
        with the prose they replace), whose "{size}" placeholder expands to
        the rung `size` datum; a size with no explicit tail composes the
        default tail "; <size> weights".
Input: dict model=merged map, ref=derived hf, id=rendered id.
*/}}
{{- define "llama-swap.deriveDisplay" -}}
{{- $m := .model -}}
{{- $parts := splitList ":" .ref -}}
{{- if lt 1 (len $parts) -}}
{{- $tag := rest $parts | join ":" -}}
{{- $disp := get $m "disp" | default (get $m "dispName") | default .id -}}
{{- $mtp := hasKey $m "draft" -}}
{{- $mtp = or $mtp (hasKey $m "spec") -}}
{{- $name := printf "%s (%s%s)" $disp $tag (ternary ", MTP" "" $mtp) -}}
{{- $suffix := get $m "suffix" -}}
{{- if $suffix -}}
{{- $name = printf "%s - %s" $name $suffix -}}
{{- end -}}
{{- if not (hasKey $m "name") -}}
{{- $_ := set $m "name" $name -}}
{{- end -}}
{{- if not (hasKey $m "description") -}}
{{- $qform := ternary "(no quant)" "quant" (or (eq $tag "BF16") (eq $tag "F16")) -}}
{{- $tail := get $m "descTail" -}}
{{- $size := get $m "size" -}}
{{- if $size -}}
{{- if $tail -}}
{{- $tail = replace "{size}" $size $tail -}}
{{- else -}}
{{- $tail = printf "; %s weights" $size -}}
{{- end -}}
{{- end -}}
{{- $desc := printf "%s, %s %s%s" (get $m "descBase" | default $disp) $tag $qform $tail -}}
{{- $_ := set $m "description" $desc -}}
{{- end -}}
{{- end -}}
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
