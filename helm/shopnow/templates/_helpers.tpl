{{/*
Expand the name of the chart.
*/}}
{{- define "shopnow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "shopnow.fullname" -}}
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
Common labels applied to all resources.
*/}}
{{- define "shopnow.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: shopnow
{{- end }}

{{/*
Selector labels for a given component.
Usage: include "shopnow.selectorLabels" (dict "component" "backend" "context" .)
*/}}
{{- define "shopnow.selectorLabels" -}}
app: {{ .component }}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end }}

{{/*
Build the full image reference for a component.
Usage: include "shopnow.image" (dict "image" .Values.backend.image "global" .Values.global)
*/}}
{{- define "shopnow.image" -}}
{{- $registry := .global.imageRegistry -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry .image.repository .image.tag -}}
{{- else -}}
{{- printf "%s:%s" .image.repository .image.tag -}}
{{- end -}}
{{- end }}

{{/*
MongoDB URI built from chart values.
*/}}
{{- define "shopnow.mongodbURI" -}}
{{- printf "mongodb://%s:%s@mongodb-service:27017/%s?authSource=admin"
    .Values.mongodb.auth.rootUsername
    .Values.mongodb.auth.rootPassword
    .Values.mongodb.auth.database -}}
{{- end }}
