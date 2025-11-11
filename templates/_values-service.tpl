{{/*
Build service structure from flat values
*/}}
{{- define "kiwix.values.service" -}}
service:
  server:
    controller: server
    ports:
      http:
        port: {{ .Values.service.port }}
{{- end -}}
