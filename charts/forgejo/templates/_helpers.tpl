{{/*
S3 LFS gate: true only where the merged values declare
STORAGE_TYPE "minio" under gitea.config.lfs. The instance's own declaration
is the switch — there is no separate boolean flag — so an instance that
keeps the LFS server on but stores objects locally simply declares nothing,
and an absent or other value means local storage on the data volume.
*/}}
{{- define "forgejo.lfs.s3.enabled" -}}
{{- eq (toString (get (get (get .Values.forgejo.gitea "config" | default dict) "lfs" | default dict) "STORAGE_TYPE" | default "")) "minio" -}}
{{- end }}
