{{/* Release-scoped name for chart-owned resources (Secret, Ingress). */}}
{{- define "plumber-platform.fullname" -}}
{{- printf "%s-plumber-platform" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "plumber-platform.labels" -}}
app.kubernetes.io/part-of: plumber-platform
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- range $key, $val := .Values.additionalLabels }}
{{ $key }}: {{ $val | quote }}
{{- end }}
{{- end }}

{{- define "plumber-platform.annotations" -}}
{{- with .Values.additionalAnnotations }}
annotations:
  {{- range $key, $val := . }}
  {{ $key }}: {{ $val | quote }}
  {{- end }}
{{- end }}
{{- end }}

{{/* App image ref: dict "root" $ "app" .Values.backend */}}
{{- define "plumber-platform.appImage" -}}
{{- if .root.Values.imageRegistry -}}
{{ .root.Values.imageRegistry }}/{{ .app.imageName }}:{{ .app.tag }}
{{- else -}}
{{ .app.image }}:{{ .app.tag }}
{{- end -}}
{{- end }}

{{/* Generic image ref for postgres/redis: [registry/]repository:tag[@digest] */}}
{{- define "plumber-platform.depImage" -}}
{{- $base := ternary (printf "%s/%s" .registry .repository) .repository (ne .registry "") -}}
{{- ternary (printf "%s:%s@%s" $base .tag .digest) (printf "%s:%s" $base .tag) (ne .digest "") -}}
{{- end }}

{{- define "plumber-platform.secretName" -}}
{{- .Values.platform.existingSecret | default (include "plumber-platform.fullname" .) -}}
{{- end }}

{{- define "plumber-platform.postgresHost" -}}
{{- .Values.postgresql.custom.host | default (printf "%s-postgresql" .Release.Name) -}}
{{- end }}

{{- define "plumber-platform.redisHost" -}}
{{- .Values.redis.custom.host | default (printf "%s-redis-master" .Release.Name) -}}
{{- end }}

{{- define "plumber-platform.dbSecretName" -}}
{{- .Values.postgresql.global.postgresql.auth.existingSecret | default (include "plumber-platform.fullname" .) -}}
{{- end }}

{{- define "plumber-platform.dbSecretKey" -}}
{{- if .Values.postgresql.global.postgresql.auth.existingSecret -}}
{{ .Values.postgresql.global.postgresql.auth.secretKeys.userPasswordKey }}
{{- else -}}
dbPassword
{{- end -}}
{{- end }}

{{- define "plumber-platform.redisAuthEnabled" -}}
{{- if or .Values.redis.auth.existingSecret .Values.redis.auth.password }}true{{ end -}}
{{- end }}

{{- define "plumber-platform.redisSecretName" -}}
{{- .Values.redis.auth.existingSecret | default (include "plumber-platform.fullname" .) -}}
{{- end }}

{{- define "plumber-platform.redisSecretKey" -}}
{{- if .Values.redis.auth.existingSecret -}}
{{ .Values.redis.auth.existingSecretPasswordKey }}
{{- else -}}
redisPassword
{{- end -}}
{{- end }}

{{- define "plumber-platform.caEnabled" -}}
{{- with .Values.customCertificateAuthority -}}
{{- if or .existingSecret .configMapName .certificates }}true{{ end -}}
{{- end -}}
{{- end }}

{{/* The ca-certificates volume source (v1 semantics: secret > configmap > generated configmap). */}}
{{- define "plumber-platform.caVolume" -}}
- name: ca-certificates
  {{- with .Values.customCertificateAuthority }}
  {{- if .existingSecret }}
  secret:
    secretName: {{ .existingSecret }}
  {{- else }}
  configMap:
    name: {{ .configMapName | default "plumber-ca-certificates" }}
  {{- end }}
  {{- end }}
{{- end }}

{{/* Backend runtime env, shared by the Deployment and the bootstrap Job. */}}
{{- define "plumber-platform.backendEnv" -}}
- name: PLUMBER_LISTEN_ADDR
  value: "0.0.0.0"
- name: PLUMBER_LISTEN_PORT
  value: {{ .Values.backend.port | quote }}
- name: PLUMBER_BASE_URL
  value: {{ required "platform.baseUrl is required (the public origin, e.g. https://plumber.example.com)" .Values.platform.baseUrl | quote }}
- name: PLUMBER_OIDC_AUDIENCE
  value: {{ .Values.platform.oidc.audience | default .Values.platform.baseUrl | quote }}
- name: PLUMBER_OIDC_ALLOWED_ISSUERS
  value: {{ (join "," .Values.platform.oidc.allowedIssuers) | default .Values.platform.gitlabUrl | quote }}
- name: PLUMBER_COOKIE_SECURE
  value: {{ .Values.platform.config.cookieSecure | quote }}
- name: PLUMBER_TRUST_FORWARDED_FOR
  value: {{ .Values.platform.config.trustForwardedFor | quote }}
{{- with .Values.platform.config.trustedProxyCidrs }}
- name: PLUMBER_TRUSTED_PROXY_CIDRS
  value: {{ join "," . | quote }}
{{- end }}
- name: PLUMBER_SESSION_TTL
  value: {{ .Values.platform.config.sessionTTL | quote }}
- name: PLUMBER_LOG_LEVEL
  value: {{ .Values.platform.config.logLevel | quote }}
- name: PLUMBER_LOG_FORMAT
  value: {{ .Values.platform.config.logFormat | quote }}
- name: PLUMBER_RETENTION_DAYS
  value: {{ .Values.platform.config.retentionDays | quote }}
{{- with .Values.platform.updateCheckUrl }}
- name: PLUMBER_UPDATE_CHECK_URL
  value: {{ . | quote }}
{{- end }}
- name: PLUMBER_DB_HOST
  value: {{ include "plumber-platform.postgresHost" . | quote }}
- name: PLUMBER_DB_PORT
  value: {{ .Values.postgresql.custom.port | quote }}
- name: PLUMBER_DB_USER
  value: {{ .Values.postgresql.global.postgresql.auth.username | quote }}
- name: PLUMBER_DB_NAME
  value: {{ .Values.postgresql.custom.dbName | quote }}
- name: PLUMBER_DB_SSLMODE
  value: {{ .Values.postgresql.custom.sslmode | quote }}
- name: PLUMBER_DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "plumber-platform.dbSecretName" . | quote }}
      key: {{ include "plumber-platform.dbSecretKey" . | quote }}
{{- if include "plumber-platform.redisAuthEnabled" . }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "plumber-platform.redisSecretName" . | quote }}
      key: {{ include "plumber-platform.redisSecretKey" . | quote }}
- name: PLUMBER_REDIS_URL
  value: {{ printf "redis://default:$(REDIS_PASSWORD)@%s:%v/%v" (include "plumber-platform.redisHost" .) .Values.redis.custom.port .Values.redis.custom.databaseIndex | quote }}
{{- else }}
- name: PLUMBER_REDIS_URL
  value: {{ printf "redis://%s:%v/%v" (include "plumber-platform.redisHost" .) .Values.redis.custom.port .Values.redis.custom.databaseIndex | quote }}
{{- end }}
- name: PLUMBER_TOKEN_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "plumber-platform.secretName" . | quote }}
      key: {{ .Values.platform.existingSecretKey | quote }}
{{- if include "plumber-platform.caEnabled" . }}
- name: PLUMBER_PROVIDER_CA_BUNDLE
  value: /etc/plumber/ca/ca-bundle.pem
{{- end }}
{{- with .Values.backend.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
