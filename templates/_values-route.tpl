{{/*
Build route structure from flat values
*/}}
{{- define "kiwix.values.route" -}}
route:
  main:
    enabled: {{ .Values.route.enabled }}
    {{- if .Values.route.enabled }}
    kind: {{ .Values.route.kind }}
    parentRefs:
      - name: {{ .Values.route.gateway.name }}
        namespace: {{ .Values.route.gateway.namespace }}
    hostnames:
      - {{ .Values.route.hostname }}
    rules:
      - backendRefs:
          - identifier: main
    {{- end }}
{{- end -}}
