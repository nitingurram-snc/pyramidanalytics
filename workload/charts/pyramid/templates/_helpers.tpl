{{/*
Expand the name of the chart.
*/}}
{{- define "pyramidAnalytics.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pyramidAnalytics.fullname" -}}
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
{{- define "pyramidAnalytics.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pyramidAnalytics.labels" -}}
helm.sh/chart: {{ include "pyramidAnalytics.chart" . }}
{{ include "pyramidAnalytics.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pyramidAnalytics.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pyramidAnalytics.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{- define "pyramidAnalytics.baseEnv" -}}
- name: PYRAMID_DOCKER_REGISTRY
  value: "{{ .Values.repo }}"
- name: host_name
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: machine_desc
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: namespace
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{- end }}


{{- define "pyramidAnalytics.podSecurityContext" -}}
  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
    runAsGroup: 1001
    fsGroup: 1001
{{- end }}

{{- define "pyramidAnalytics.containerSecurityContext" -}}
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
{{- end }}

{{- define "pyramidAnalytics.mount" -}}
{{- if (not (eq "other" $.Values.storage.type)) }}
    volumeMounts:
    - name: persistent-storage
      mountPath: /opt/pyramid-repo
{{- end }}
{{- end }}

{{- define "pyramidAnalytics.volume" -}}
{{- if (not (eq "other" $.Values.storage.type)) }}
volumes:
- name: persistent-storage
  persistentVolumeClaim:
    claimName: {{ $.Values.storage.claim.name }}
{{- end }}
{{- end }}

{{- define "pyramidAnalytics.unattended.json" -}}
{{- if .Values.unattended.enabled -}}
{{- /* Render the json field for unattended installation by converting .Values.unattended.installationData to json */ -}}
{{- with $dict := deepCopy .Values.unattended.installationData -}}
json: '{{ $dict | toJson }}'
{{- end }}
{{- end }}
{{- end }}
