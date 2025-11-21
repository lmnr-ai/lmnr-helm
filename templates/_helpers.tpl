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