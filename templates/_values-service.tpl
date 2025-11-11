{{/*
Build service structure from flat values
*/}}
{{- define "kiwix.values.service" -}}
service:
  main:
    controller: main
    ports:
      http:
        port: {{ .Values.service.port }}
{{- end -}}
