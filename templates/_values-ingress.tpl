{{/*
Build ingress structure from flat values
*/}}
{{- define "kiwix.values.ingress" -}}
ingress:
  server:
    enabled: {{ .Values.ingress.enabled }}
    {{- if .Values.ingress.enabled }}
    hosts:
      - host: {{ .Values.ingress.host }}
        paths:
          - path: {{ .Values.ingress.path }}
            pathType: {{ .Values.ingress.pathType }}
            service:
              identifier: server
              port: http
    {{- end }}
{{- end -}}
