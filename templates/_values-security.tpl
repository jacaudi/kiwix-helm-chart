{{/*
Build defaultPodOptions structure from flat values
*/}}
{{- define "kiwix.values.security" -}}
defaultPodOptions:
  securityContext:
    fsGroup: {{ .Values.security.fsGroup }}
    fsGroupChangePolicy: {{ .Values.security.fsGroupChangePolicy | quote }}
{{- end -}}
