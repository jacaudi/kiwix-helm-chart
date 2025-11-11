{{/*
Build persistence structure from flat values
*/}}
{{- define "kiwix.values.persistence" -}}
persistence:
  data:
    enabled: true
    type: persistentVolumeClaim
    accessMode: {{ .Values.persistence.accessMode }}
    size: {{ .Values.persistence.size }}
    {{- with .Values.persistence.storageClass }}
    storageClass: {{ . }}
    {{- end }}
    retain: {{ .Values.persistence.retain }}
    globalMounts:
      - path: /data
  config:
    enabled: true
    type: configMap
    name: "{{ include "bjw-s.common.lib.chart.names.fullname" $ }}-zim-urls"
    advancedMounts:
      downloader:
        main:
          - path: /config
            readOnly: true
{{- end -}}
