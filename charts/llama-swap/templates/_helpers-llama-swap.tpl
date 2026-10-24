{{/*
llama-swap.declaredConfig renders the llama-swap config.yaml from the compact
roster schema in .Values.config (CA2, plan REPLAN CR1; CR5 derivation):

- config.families is the FULL catalog: every family x rung pair expands into
  one model entry. Field merge layering is family < rung < raw config.models
  (deep merge; lists replace wholesale, same semantics as Helm's own value
  layering - CA2 note "per-rung use/flags overrides are full replacements").
  The rendered ID is rung.id | "<family>-<quant>"; a derived ID seen twice
  fails the render: under one file, a duplicate silently drops an entry
  from the rendered model map.
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

macros/matrix/hooks are top-level llama-swap config keys: .Values.config
passes them through unchanged and only `models:` is derived above - matrix
vars name rendered model ids, so they must live in the same file as the
roster they address.
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
