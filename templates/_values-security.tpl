{{/*
Build defaultPodOptions structure from flat values
*/}}
{{- define "kiwix.values.security" -}}
defaultPodOptions:
  enableServiceLinks: false
  hostIPC: false
  hostNetwork: false
  hostPID: false
  securityContext:
    fsGroup: {{ .Values.security.fsGroup }}
    fsGroupChangePolicy: {{ .Values.security.fsGroupChangePolicy | quote }}
{{- end -}}
