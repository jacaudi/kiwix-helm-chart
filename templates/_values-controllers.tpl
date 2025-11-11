{{/*
Build controllers structure from flat values
*/}}
{{- define "kiwix.values.controllers" -}}
controllers:
  server:
    strategy: {{ .Values.kiwix.strategy }}
    containers:
      main:
        image:
          repository: {{ .Values.images.kiwix.repository }}
          tag: {{ .Values.images.kiwix.tag }}
          pullPolicy: {{ .Values.images.kiwix.pullPolicy }}
        args: {{- toYaml .Values.kiwix.args | nindent 10 }}
        probes:
          liveness:
            enabled: {{ .Values.kiwix.probes.liveness.enabled }}
            custom: true
            spec:
              httpGet:
                path: {{ .Values.kiwix.probes.liveness.path }}
                port: {{ .Values.kiwix.probes.liveness.port }}
          readiness:
            enabled: {{ .Values.kiwix.probes.readiness.enabled }}
            custom: true
            spec:
              httpGet:
                path: {{ .Values.kiwix.probes.readiness.path }}
                port: {{ .Values.kiwix.probes.readiness.port }}
        {{- with .Values.kiwix.resources }}
        resources: {{- toYaml . | nindent 10 }}
        {{- end }}
  {{- if .Values.downloader.enabled }}
  downloader:
    enabled: true
    {{- if .Values.downloader.schedule }}
    type: cronjob
    cronjob:
      schedule: {{ .Values.downloader.schedule | quote }}
      {{- with .Values.downloader.maxRuntime }}
      activeDeadlineSeconds: {{ . }}
      {{- end }}
      {{- with .Values.downloader.cleanupAfter }}
      ttlSecondsAfterFinished: {{ . }}
      {{- end }}
    {{- else }}
    type: job
    job:
      {{- with .Values.downloader.maxRuntime }}
      activeDeadlineSeconds: {{ . }}
      {{- end }}
      {{- with .Values.downloader.cleanupAfter }}
      ttlSecondsAfterFinished: {{ . }}
      {{- end }}
    {{- end }}
    containers:
      main:
        image:
          repository: {{ .Values.images.downloader.repository }}
          tag: {{ .Values.images.downloader.tag }}
          pullPolicy: {{ .Values.images.downloader.pullPolicy }}
        {{- with .Values.downloader.resources }}
        resources: {{- toYaml . | nindent 10 }}
        {{- end }}
  {{- end }}
{{- end -}}
