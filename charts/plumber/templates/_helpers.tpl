{{/*
Build the Redis image reference from values.
Produces: [registry/]repository:tag[@digest]
*/}}
{{- define "plumber.redisImage" -}}
{{- $reg  := .Values.redis.image.registry -}}
{{- $repo := .Values.redis.image.repository -}}
{{- $tag  := .Values.redis.image.tag -}}
{{- $dig  := .Values.redis.image.digest -}}
{{- $base := ternary (printf "%s/%s" $reg $repo) $repo (ne $reg "") -}}
{{- ternary (printf "%s:%s@%s" $base $tag $dig) (printf "%s:%s" $base $tag) (ne $dig "") -}}
{{- end }}
