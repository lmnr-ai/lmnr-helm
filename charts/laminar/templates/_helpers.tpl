{{/*
Expand the name of the chart.
*/}}
{{- define "laminar.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "laminar.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "laminar.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "laminar.labels" -}}
helm.sh/chart: {{ include "laminar.chart" . }}
{{ include "laminar.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "laminar.selectorLabels" -}}
app.kubernetes.io/name: {{ include "laminar.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Standard annotations
*/}}
{{- define "laminar.annotations" -}}
meta.helm.sh/release-name: {{ .Release.Name }}
meta.helm.sh/release-namespace: {{ .Release.Namespace }}
{{- end }}

{{/*
Namespace - returns the namespace to use for resources
*/}}
{{- define "laminar.namespace" -}}
{{- .Release.Namespace | default .Values.global.namespace | default "default" }}
{{- end }}

{{/*
Resource Name - prefixes resource names with "laminar-" unless already prefixed
Skips prefixing for resources already starting with "lmnr-" or "laminar-"
Usage: {{ include "laminar.resourceName" "frontend" }}
*/}}
{{- define "laminar.resourceName" -}}
{{- $name := . -}}
{{- if or (hasPrefix "lmnr-" $name) (hasPrefix "laminar-" $name) -}}
{{- $name -}}
{{- else -}}
{{- printf "laminar-%s" $name -}}
{{- end -}}
{{- end }}

{{/*
Resolve the StorageClass for a persistent service. An explicit per-service
class wins. Otherwise, use the chart-managed class when it is enabled. Return
an empty string when it is disabled so storageClassName can be omitted and
Kubernetes can select a cluster default StorageClass.
Usage: {{ include "lmnr.storageClassName" (dict "root" . "persistence" .Values.postgres.persistence) }}
*/}}
{{- define "lmnr.storageClassName" -}}
{{- if .persistence.storageClass -}}
{{- .persistence.storageClass -}}
{{- else if ne .root.Values.storage.storageClass.enabled false -}}
{{- include "laminar.resourceName" .root.Values.storage.storageClass.name -}}
{{- end -}}
{{- end }}

{{/*
Node selector - merges service-specific with global defaults
Usage: {{ include "laminar.nodeSelector" (dict "service" .Values.frontend "global" .Values.global) }}
*/}}
{{- define "laminar.nodeSelector" -}}
{{- $nodeSelector := dict }}
{{- if .global.nodeSelector }}
{{- $nodeSelector = merge $nodeSelector .global.nodeSelector }}
{{- end }}
{{- if .service.nodeSelector }}
{{- $nodeSelector = merge $nodeSelector .service.nodeSelector }}
{{- end }}
{{- if $nodeSelector }}
nodeSelector:
  {{- toYaml $nodeSelector | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Affinity - uses service-specific affinity or falls back to global nodeGroupName if set
Usage: {{ include "laminar.affinity" (dict "service" .Values.frontend "global" .Values.global) }}
*/}}
{{- define "laminar.affinity" -}}
{{- if .service.affinity }}
affinity:
  {{- toYaml .service.affinity | nindent 2 }}
{{- else if .global.affinity }}
affinity:
  {{- toYaml .global.affinity | nindent 2 }}
{{- else if .global.nodeGroupName }}
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: alpha.eksctl.io/nodegroup-name
          operator: In
          values:
          - {{ .global.nodeGroupName }}
{{- end }}
{{- end }}

{{/*
Tolerations - merges service-specific with global defaults
Usage: {{ include "laminar.tolerations" (dict "service" .Values.frontend "global" .Values.global) }}
*/}}
{{- define "laminar.tolerations" -}}
{{- $tolerations := list }}
{{- if .global.tolerations }}
{{- $tolerations = concat $tolerations .global.tolerations }}
{{- end }}
{{- if .service.tolerations }}
{{- $tolerations = concat $tolerations .service.tolerations }}
{{- end }}
{{- if $tolerations }}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Secrets Management Helpers
*/}}

{{/*
Check if AWS Secrets Manager is enabled
*/}}
{{- define "lmnr.secrets.awsEnabled" -}}
{{- if and .Values.secrets.awsSecretsManager .Values.secrets.awsSecretsManager.enabled }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Check if Vault is enabled
*/}}
{{- define "lmnr.secrets.vaultEnabled" -}}
{{- if and .Values.secrets.vault .Values.secrets.vault.enabled }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Check if any external secret provider needs CSI mount
*/}}
{{- define "lmnr.secrets.needsCSIMount" -}}
{{- if or (include "lmnr.secrets.awsEnabled" .) (include "lmnr.secrets.vaultEnabled" .) }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Generate AWS secret name from clusterName or use explicit secretName
*/}}
{{- define "lmnr.secrets.awsSecretName" -}}
{{- if .Values.secrets.awsSecretsManager.secretName }}
{{- .Values.secrets.awsSecretsManager.secretName }}
{{- else if .Values.secrets.awsSecretsManager.clusterName }}
{{- printf "%s/lmnr-secrets" .Values.secrets.awsSecretsManager.clusterName }}
{{- else }}
{{- fail "AWS Secrets Manager is enabled but neither secretName nor clusterName is set" }}
{{- end }}
{{- end }}

{{/*
Return the appropriate service account name for secrets
*/}}
{{- define "lmnr.secrets.serviceAccountName" -}}
{{- if include "lmnr.secrets.awsEnabled" . }}
{{- .Values.secrets.awsSecretsManager.serviceAccount.name }}
{{- else if include "lmnr.secrets.vaultEnabled" . }}
{{- .Values.secrets.vault.serviceAccount.name }}
{{- else }}
{{- "default" }}
{{- end }}
{{- end }}

{{/*
Generate envFrom for loading secrets from all applicable sources
*/}}
{{- define "lmnr.secrets.envFrom" -}}
- secretRef:
    name: {{ include "laminar.resourceName" "app-secrets" }}
{{- if include "lmnr.secrets.awsEnabled" . }}
- secretRef:
    name: {{ include "laminar.resourceName" "app-secrets-aws" }}
{{- end }}
{{- if include "lmnr.secrets.vaultEnabled" . }}
- secretRef:
    name: {{ include "laminar.resourceName" "app-secrets-vault" }}
{{- end }}
{{- end }}

{{/*
Quickwit per-component extraEnv. Renders chart-wide quickwit.extraEnv
followed by the component's own extraEnv (later wins on duplicate names —
matches Kubernetes semantics for the env array).
Usage: {{ include "lmnr.quickwit.extraEnv" (dict "root" . "component" .Values.quickwit.indexer) }}
*/}}
{{- define "lmnr.quickwit.extraEnv" -}}
{{- $envs := concat (.root.Values.quickwit.extraEnv | default list) (.component.extraEnv | default list) -}}
{{- with $envs }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Quickwit master gate. Returns "true" when Quickwit should be deployed AND
the app pods should advertise QUICKWIT_SEARCH_URL / QUICKWIT_INGEST_URL.
Both conditions must hold:
  - .Values.quickwit.enabled (operator opt-in / explicit disable)
  - .Values.quickwit.s3.defaultIndexRootUri non-empty
The bucket gate prevents Quickwit from spinning up against a placeholder
bucket name and silently creating indexes the operator can't write to.
*/}}
{{- define "lmnr.quickwit.enabled" -}}
{{- if and .Values.quickwit.enabled .Values.quickwit.s3.defaultIndexRootUri -}}
true
{{- end -}}
{{- end }}

{{/*
Enforce the minimum app-server image tag. Chart 0.2.0 folded the former
query-engine workload into the app-server image; tags below 0.1.628 ship
without it and would break at runtime (see CHANGELOG.md).

Only enforced when the tag is a recognizable semver. The core X.Y.Z is
compared in isolation, ignoring any -prerelease / +build suffix, so our own
decorated tags (0.1.628-post.1, 0.1.628-alpha, 0.1.628-canary.3, ...) pass on
their core version rather than sorting below the floor under strict semver
precedence. Non-semver tags ("latest", branch names, digests) are trusted and
skipped — pinning those is the operator's responsibility.
*/}}
{{- define "lmnr.validateAppServerVersion" -}}
{{- $tag := .Values.images.appServer.tag | toString -}}
{{- $min := "0.1.628" -}}
{{- if regexMatch "^v?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$" $tag -}}
{{- $core := regexFind "[0-9]+\\.[0-9]+\\.[0-9]+" $tag -}}
{{- if semverCompare (printf "< %s" $min) $core -}}
{{- fail (printf "images.appServer.tag %q is incompatible with chart %s: chart >= 0.2.0 requires app-server >= %s (the query-engine was folded into the app-server image; older tags omit it). Set images.appServer.tag to %s or newer, or to \"latest\". See CHANGELOG.md." $tag .Chart.Version $min $min) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Resolve NEXT_PUBLIC_URL for a given service. Accepts a dict with keys
"service" (the per-service .env map) and "global" (.Values.global).
Returns the per-service override when non-empty, else falls back to
global.nextPublicUrl. The same value is dispatched to frontend,
app-server, and app-server-consumer so alert/notification URLs and
lmnr-cli auth all agree.
*/}}
{{- define "lmnr.nextPublicUrl" -}}
{{- if .service.nextPublicUrl -}}
{{- .service.nextPublicUrl -}}
{{- else -}}
{{- .global.nextPublicUrl -}}
{{- end -}}
{{- end }}

{{/*
Frontend sub-path prefix (LAM-1749). Returns the fixed "/lmnr" when
frontend.subPath.enabled is true, else empty. The prefix is baked into the
frontend image at build time (Next.js inlines it into the standalone bundle's
asset URLs — it can't be flipped at runtime), so it's fixed to match the
published frontend-ee-basepath image and is NOT operator-configurable.
*/}}
{{- define "lmnr.frontend.subPath" -}}
{{- if .Values.frontend.subPath.enabled -}}/lmnr{{- end -}}
{{- end }}

{{/*
Frontend image name. Forces the prebuilt frontend-ee-basepath image (baked
with NEXT_PUBLIC_BASE_PATH=/lmnr) when sub-path serving is enabled, else uses
the configured images.frontend.name. Driving both the image and the ingress
path from one bool removes the old footgun where they could disagree.
*/}}
{{- define "lmnr.frontend.imageName" -}}
{{- if .Values.frontend.subPath.enabled -}}frontend-ee-basepath{{- else -}}{{ .Values.images.frontend.name }}{{- end -}}
{{- end }}

{{/*
Parse a size quantity into an integer byte count. Accepts Kubernetes
quantities ("4Gi", "512Mi", "0.5Gi", "4G") and RabbitMQ-style units ("2GB",
"50MiB"); a bare number is bytes. Decimal suffixes are powers of 1000,
binary (i) suffixes powers of 1024.
Usage: {{ include "lmnr.bytes" "4Gi" }}
*/}}
{{- define "lmnr.bytes" -}}
{{- if not (kindIs "string" .) -}}
{{- /* YAML numbers arrive as float64; toString would print 2.62144e+07 */ -}}
{{- . | int64 -}}
{{- else -}}
{{- $q := . | trim -}}
{{- $num := regexFind "^[0-9]+(\\.[0-9]+)?" $q -}}
{{- $unit := trimPrefix $num $q | trim -}}
{{- $units := dict "" 1.0 "k" 1e3 "K" 1e3 "kB" 1e3 "KB" 1e3 "M" 1e6 "MB" 1e6 "G" 1e9 "GB" 1e9 "T" 1e12 "TB" 1e12 "Ki" 1024.0 "KiB" 1024.0 "Mi" 1048576.0 "MiB" 1048576.0 "Gi" 1073741824.0 "GiB" 1073741824.0 "Ti" 1099511627776.0 "TiB" 1099511627776.0 -}}
{{- if or (not $num) (not (hasKey $units $unit)) -}}
{{- fail (printf "cannot parse size %q (expected e.g. 4Gi, 512Mi, 2GB)" $q) -}}
{{- end -}}
{{- mulf (float64 $num) (index $units $unit) | floor | int64 -}}
{{- end -}}
{{- end }}

{{/*
RabbitMQ Streams helpers. Everything stream-related that the app pods read is
emitted by "lmnr.rabbitmq.streams.env" from the single rabbitmq.streams block,
so the producer (app-server) and consumer (app-server-consumer) can never
disagree on topology or on whether the indexer stream has a reader.
*/}}

{{/* Number of super streams the app may declare (spans + Quickwit indexer).
Counted as 2 even with the indexer off: retention is creation-only, so the
budget must already cover the indexer stream if it is turned on later. */}}
{{- define "lmnr.rabbitmq.streams.count" -}}2{{- end }}

{{- define "lmnr.rabbitmq.streams.host" -}}
{{- if .Values.rabbitmq.streams.host -}}
{{- .Values.rabbitmq.streams.host -}}
{{- else -}}
{{- include "laminar.resourceName" "rabbitmq-service" -}}
{{- end -}}
{{- end }}

{{- define "lmnr.rabbitmq.streams.replicationFactor" -}}
{{- $s := .Values.rabbitmq.streams -}}
{{- if $s.replicationFactor -}}
{{- $s.replicationFactor | int -}}
{{- else if .Values.rabbitmq.enabled -}}
{{- min 2 (.Values.rabbitmq.replicaCount | int) -}}
{{- else -}}
2
{{- end -}}
{{- end }}

{{/* Per-partition retention cap. Explicit value wins; otherwise half of the
RabbitMQ volume is split across every partition of every super stream. */}}
{{- define "lmnr.rabbitmq.streams.maxLengthBytes" -}}
{{- $s := .Values.rabbitmq.streams -}}
{{- if $s.maxLengthBytes -}}
{{- include "lmnr.bytes" $s.maxLengthBytes -}}
{{- else if not (and .Values.rabbitmq.enabled .Values.rabbitmq.persistence.enabled) -}}
{{- fail "rabbitmq.streams.maxLengthBytes must be set explicitly when rabbitmq.enabled or rabbitmq.persistence.enabled is false: the chart can only derive stream retention from the in-chart RabbitMQ volume size" -}}
{{- else -}}
{{- $disk := include "lmnr.bytes" .Values.rabbitmq.persistence.size | int64 -}}
{{- $slots := mul (include "lmnr.rabbitmq.streams.count" . | int64) ($s.partitions | int64) -}}
{{- div (div $disk 2) $slots -}}
{{- end -}}
{{- end }}

{{/* Per-reader memory budget. Explicit value wins; otherwise
appServerConsumer.resources.limits.memory / 32 clamped to [16Mi, 128Mi]. */}}
{{- define "lmnr.rabbitmq.streams.channelMaxBytes" -}}
{{- $r := .Values.rabbitmq.streams.reader -}}
{{- $floor := 16777216 -}}
{{- $ceil := 134217728 -}}
{{- if $r.channelMaxBytes -}}
{{- include "lmnr.bytes" $r.channelMaxBytes -}}
{{- else -}}
{{- $limit := dig "limits" "memory" "" (.Values.appServerConsumer.resources | default dict) -}}
{{- if $limit -}}
{{- div (include "lmnr.bytes" $limit | int64) 32 | max $floor | min $ceil -}}
{{- else -}}
{{- $ceil -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/* Render-time checks; fail fast instead of shipping a broker that blocks
publishers on a full disk or a client that can't reach partition leaders. */}}
{{- define "lmnr.rabbitmq.streams.validate" -}}
{{- $s := .Values.rabbitmq.streams -}}
{{- if lt ($s.partitions | int) 1 -}}
{{- fail "rabbitmq.streams.partitions must be >= 1" -}}
{{- end -}}
{{- if .Values.rabbitmq.enabled -}}
{{- if not .Values.rabbitmq.headlessService.enabled -}}
{{- fail "rabbitmq.streams.enabled requires rabbitmq.headlessService.enabled: stream clients dial each broker pod by its headless-service DNS name" -}}
{{- end -}}
{{- $rf := include "lmnr.rabbitmq.streams.replicationFactor" . | int -}}
{{- if or (lt $rf 1) (gt $rf (.Values.rabbitmq.replicaCount | int)) -}}
{{- fail (printf "rabbitmq.streams.replicationFactor (%d) must be between 1 and rabbitmq.replicaCount (%d)" $rf (.Values.rabbitmq.replicaCount | int)) -}}
{{- end -}}
{{- if .Values.rabbitmq.persistence.enabled -}}
{{- $maxLen := include "lmnr.rabbitmq.streams.maxLengthBytes" . | int64 -}}
{{- $total := mul (include "lmnr.rabbitmq.streams.count" . | int64) ($s.partitions | int64) $maxLen -}}
{{- $disk := include "lmnr.bytes" .Values.rabbitmq.persistence.size | int64 -}}
{{- $usable := sub $disk (include "lmnr.bytes" .Values.rabbitmq.config.diskFreeLimit | int64) -}}
{{- if gt $total $usable -}}
{{- fail (printf "RabbitMQ streams can occupy %d bytes (2 streams × %d partitions × %d maxLengthBytes), which exceeds rabbitmq.persistence.size (%s) minus config.diskFreeLimit (%s). Lower rabbitmq.streams.maxLengthBytes or grow the volume; a full disk blocks every publisher." $total ($s.partitions | int) $maxLen .Values.rabbitmq.persistence.size .Values.rabbitmq.config.diskFreeLimit) -}}
{{- end -}}
{{- end -}}
{{- else if not $s.host -}}
{{- fail "rabbitmq.streams.host must be set when rabbitmq.enabled is false" -}}
{{- end -}}
{{- end }}

{{/*
Stream env vars for an app-server pod. Pass (dict "root" . "consumer" true)
from app-server-consumer to add the reader tuning. Credentials reuse the
broker's default user via $(VAR) expansion of the envFrom secrets, so they
work for every secrets source (k8s / AWS / Vault). Override
RABBITMQ_STREAM_USERNAME / RABBITMQ_STREAM_PASSWORD via extraEnv for an
external broker with different credentials.
*/}}
{{- define "lmnr.rabbitmq.streams.env" -}}
{{- $root := .root -}}
{{- $s := $root.Values.rabbitmq.streams -}}
{{- if $s.enabled -}}
{{- include "lmnr.rabbitmq.streams.validate" $root -}}
- name: RABBITMQ_STREAMS_ENABLED
  value: "true"
- name: RABBITMQ_STREAM_HOST
  value: {{ include "lmnr.rabbitmq.streams.host" $root | quote }}
- name: RABBITMQ_STREAM_PORT
  value: {{ $s.port | quote }}
- name: RABBITMQ_STREAM_USERNAME
  value: "$(RABBITMQ_DEFAULT_USER)"
- name: RABBITMQ_STREAM_PASSWORD
  value: "$(RABBITMQ_DEFAULT_PASS)"
- name: RABBITMQ_STREAM_LOAD_BALANCER_MODE
  value: {{ $s.loadBalancerMode | quote }}
- name: RABBITMQ_STREAM_SPANS_INDEXER_ENABLED
  value: {{ $s.indexerEnabled | quote }}
- name: RABBITMQ_STREAM_PARTITIONS
  value: {{ $s.partitions | int | quote }}
- name: RABBITMQ_STREAM_REPLICATION_FACTOR
  value: {{ include "lmnr.rabbitmq.streams.replicationFactor" $root | quote }}
- name: RABBITMQ_STREAM_MAX_LENGTH_BYTES
  value: {{ include "lmnr.rabbitmq.streams.maxLengthBytes" $root | quote }}
- name: RABBITMQ_STREAM_MAX_AGE_SECS
  value: {{ $s.maxAgeSecs | int64 | quote }}
- name: RABBITMQ_STREAM_MAX_SEGMENT_SIZE_BYTES
  value: {{ include "lmnr.bytes" $s.maxSegmentSizeBytes | quote }}
{{- if .consumer }}
- name: RABBITMQ_STREAM_SPANS_BATCHERS
  value: {{ $s.reader.spansBatchers | int | quote }}
- name: RABBITMQ_STREAM_SPANS_INDEXER_BATCHERS
  value: {{ $s.reader.spansIndexerBatchers | int | quote }}
- name: RABBITMQ_STREAM_CHANNEL_MAX_BYTES
  value: {{ include "lmnr.rabbitmq.streams.channelMaxBytes" $root | quote }}
- name: RABBITMQ_STREAM_CLIENT_CHANNEL_CAPACITY
  value: {{ $s.reader.clientChannelCapacity | int | quote }}
{{- end }}
{{- end -}}
{{- end }}
