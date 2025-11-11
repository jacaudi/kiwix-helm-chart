{{/*
Build ingress structure from flat values
*/}}
{{- define "kiwix.values.ingress" -}}
ingress:
  main:
    enabled: {{ .Values.ingress.enabled }}
    {{- if .Values.ingress.enabled }}
    hosts:
      - host: {{ .Values.ingress.host }}
        paths:
          - path: {{ .Values.ingress.path }}
            pathType: {{ .Values.ingress.pathType }}
            service:
              identifier: main
              port: http
    {{- end }}
{{- end -}}
