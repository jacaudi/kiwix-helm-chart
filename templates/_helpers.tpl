{{/* vim: set filetype=mustache: */}}
{{/*
Return the full name for the chart
*/}}
{{- define "kiwix.fullname" -}}
{{- include "bjw-s.common.lib.chart.names.fullname" . -}}
{{- end -}}
