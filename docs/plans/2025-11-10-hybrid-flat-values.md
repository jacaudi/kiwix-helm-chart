# Hybrid Flat Values Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor values.yaml to a flatter, simpler structure while maintaining compatibility with bjw-s common library v4.4.0

**Architecture:** Create helper templates that transform flat, user-friendly values into the nested structure expected by bjw-s common library. The new values.yaml will have 2-3 nesting levels instead of 5+ and eliminate duplication between top-level `downloader` and `controllers.downloader`.

**Tech Stack:** Helm 3, bjw-s common library v4.4.0, Kubernetes

---

## Task 1: Capture Baseline (Current Output)

**Files:**
- Read: `values.yaml`
- Create: `docs/baseline-output.yaml`

**Step 1: Generate current helm template output**

Run:
```bash
helm template kiwix . > docs/baseline-output.yaml
```

Expected: Successfully generates template output with current values

**Step 2: Verify baseline is valid**

Run:
```bash
helm lint .
```

Expected: No errors, chart passes linting

**Step 3: Commit baseline**

```bash
git add docs/baseline-output.yaml
git commit -m "docs: capture baseline helm template output before refactor"
```

---

## Task 2: Create New Values Structure

**Files:**
- Modify: `values.yaml` (complete rewrite)
- Backup: `values.yaml.backup`

**Step 1: Backup current values**

Run:
```bash
cp values.yaml values.yaml.backup
```

Expected: Backup created

**Step 2: Replace values.yaml with hybrid flat structure**

Replace entire content of `values.yaml`:

```yaml
# Global settings
global:
  fullnameOverride: ""
  nameOverride: ""

# Application images
images:
  kiwix:
    repository: ghcr.io/kiwix/kiwix-serve
    tag: latest
    pullPolicy: IfNotPresent
  downloader:
    repository: ghcr.io/jacaudi/kiwix-downloader
    tag: latest
    pullPolicy: IfNotPresent

# ZIM files to download
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim
    sha256: null

# Downloader configuration (single source of truth)
downloader:
  enabled: true
  schedule: ""  # Empty = Job, cron format (e.g., "0 2 * * 0") = CronJob
  resources: {}

# Main kiwix-serve application
kiwix:
  strategy: Recreate
  args:
    - /data/*.zim
  resources: {}
  probes:
    liveness:
      enabled: true
      path: /
      port: 8080
    readiness:
      enabled: true
      path: /
      port: 8080

# Service configuration
service:
  port: 8080

# Storage
persistence:
  size: 100Gi
  storageClass: ""
  accessMode: ReadWriteOnce
  retain: true

# Ingress (disabled by default)
ingress:
  enabled: false
  host: kiwix.local
  path: /
  pathType: Prefix

# Gateway API Route (disabled by default)
route:
  enabled: false
  kind: HTTPRoute
  gateway:
    name: ""
    namespace: ""
  hostname: kiwix.local

# Security settings
security:
  fsGroup: 1000
  fsGroupChangePolicy: "OnRootMismatch"
```

**Step 3: Verify syntax**

Run:
```bash
helm lint . 2>&1 | head -20
```

Expected: Will show errors about missing bjw-s structure (this is expected, we'll fix in next tasks)

**Step 4: DO NOT COMMIT YET**

Wait until templates are updated to avoid breaking chart

---

## Task 3: Create Controllers Helper Template

**Files:**
- Create: `templates/_values-controllers.tpl`

**Step 1: Create controllers helper**

Create `templates/_values-controllers.tpl`:

```yaml
{{/*
Build controllers structure from flat values
*/}}
{{- define "kiwix.values.controllers" -}}
controllers:
  main:
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
    {{- else }}
    type: job
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
```

**Step 2: Verify template syntax**

Run:
```bash
helm template kiwix . --debug 2>&1 | grep -A 5 "controllers:" || echo "Template not yet integrated"
```

Expected: Template not yet integrated (we'll integrate in Task 7)

---

## Task 4: Create Service Helper Template

**Files:**
- Create: `templates/_values-service.tpl`

**Step 1: Create service helper**

Create `templates/_values-service.tpl`:

```yaml
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
```

**Step 2: Verify template syntax**

Run:
```bash
helm template kiwix . --debug 2>&1 | grep -A 5 "service:" || echo "Template not yet integrated"
```

Expected: Template not yet integrated

---

## Task 5: Create Persistence Helper Template

**Files:**
- Create: `templates/_values-persistence.tpl`

**Step 1: Create persistence helper**

Create `templates/_values-persistence.tpl`:

```yaml
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
    name: "{{ include \"bjw-s.common.lib.chart.names.fullname\" $ }}-zim-urls"
    advancedMounts:
      downloader:
        main:
          - path: /config
            readOnly: true
{{- end -}}
```

**Step 2: Verify template syntax**

Run:
```bash
helm template kiwix . --debug 2>&1 | grep -A 5 "persistence:" || echo "Template not yet integrated"
```

Expected: Template not yet integrated

---

## Task 6: Create Ingress and Route Helper Templates

**Files:**
- Create: `templates/_values-ingress.tpl`
- Create: `templates/_values-route.tpl`

**Step 1: Create ingress helper**

Create `templates/_values-ingress.tpl`:

```yaml
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
```

**Step 2: Create route helper**

Create `templates/_values-route.tpl`:

```yaml
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
```

**Step 3: Verify template syntax**

Run:
```bash
helm template kiwix . --debug 2>&1 | grep -E "(ingress:|route:)" || echo "Template not yet integrated"
```

Expected: Template not yet integrated

---

## Task 7: Create Security Helper Template

**Files:**
- Create: `templates/_values-security.tpl`

**Step 1: Create security helper**

Create `templates/_values-security.tpl`:

```yaml
{{/*
Build defaultPodOptions structure from flat values
*/}}
{{- define "kiwix.values.security" -}}
defaultPodOptions:
  securityContext:
    fsGroup: {{ .Values.security.fsGroup }}
    fsGroupChangePolicy: {{ .Values.security.fsGroupChangePolicy | quote }}
{{- end -}}
```

**Step 2: Verify template syntax**

Run:
```bash
helm template kiwix . --debug 2>&1 | grep -A 3 "defaultPodOptions:" || echo "Template not yet integrated"
```

Expected: Template not yet integrated

---

## Task 8: Integrate Helpers into common.yaml

**Files:**
- Modify: `templates/common.yaml`

**Step 1: Read current common.yaml**

Current content:
```yaml
{{- /* Set downloader type to cronjob if schedule is provided */ -}}
{{- if .Values.downloader.schedule -}}
{{- $_ := set .Values.controllers.downloader "type" "cronjob" -}}
{{- end -}}
{{- include "bjw-s.common.loader.all" . }}
```

**Step 2: Replace with helper-based approach**

Replace entire content of `templates/common.yaml`:

```yaml
{{- /*
Build bjw-s values structure from flat values
*/ -}}
{{- $bjwsValues := dict -}}

{{- /* Merge in global */ -}}
{{- $_ := set $bjwsValues "global" .Values.global -}}

{{- /* Build each section using helpers */ -}}
{{- $security := include "kiwix.values.security" . | fromYaml -}}
{{- $_ := set $bjwsValues "defaultPodOptions" $security.defaultPodOptions -}}

{{- $controllers := include "kiwix.values.controllers" . | fromYaml -}}
{{- $_ := set $bjwsValues "controllers" $controllers.controllers -}}

{{- $service := include "kiwix.values.service" . | fromYaml -}}
{{- $_ := set $bjwsValues "service" $service.service -}}

{{- $persistence := include "kiwix.values.persistence" . | fromYaml -}}
{{- $_ := set $bjwsValues "persistence" $persistence.persistence -}}

{{- $ingress := include "kiwix.values.ingress" . | fromYaml -}}
{{- $_ := set $bjwsValues "ingress" $ingress.ingress -}}

{{- $route := include "kiwix.values.route" . | fromYaml -}}
{{- $_ := set $bjwsValues "route" $route.route -}}

{{- /* Create new root context with bjw-s values */ -}}
{{- $root := deepCopy . -}}
{{- $_ := set $root "Values" $bjwsValues -}}

{{- /* Include bjw-s common loader with constructed values */ -}}
{{- include "bjw-s.common.loader.all" $root }}
```

**Step 3: Verify template renders**

Run:
```bash
helm template kiwix . > /tmp/new-output.yaml 2>&1
echo "Exit code: $?"
```

Expected: Exit code 0, no errors

**Step 4: Commit the integration**

```bash
git add templates/common.yaml templates/_values-*.tpl values.yaml
git commit -m "refactor: implement hybrid flat values structure

- Flatten values.yaml from 5+ to 2-3 nesting levels
- Eliminate duplication between downloader configs
- Add helper templates to map flat -> bjw-s structure
- Maintain full compatibility with bjw-s common v4.4.0"
```

---

## Task 9: Compare Output (Functional Equivalence Test)

**Files:**
- Read: `docs/baseline-output.yaml`
- Create: `/tmp/new-output.yaml`

**Step 1: Generate new output**

Run:
```bash
helm template kiwix . > /tmp/new-output.yaml
```

Expected: Successfully generates template output

**Step 2: Compare outputs (ignore order differences)**

Run:
```bash
# Extract just the resource definitions (skip comments/metadata timestamps)
diff <(grep -v "^#" docs/baseline-output.yaml | grep -v "helm.sh/chart" | sort) \
     <(grep -v "^#" /tmp/new-output.yaml | grep -v "helm.sh/chart" | sort) \
     || echo "Differences found - review carefully"
```

Expected: Minimal or no differences (some label/annotation order changes are OK)

**Step 3: Verify critical resources unchanged**

Run:
```bash
# Check PVC size
grep -A 5 "PersistentVolumeClaim" /tmp/new-output.yaml | grep "storage:"

# Check service port
grep -A 5 'kind: Service' /tmp/new-output.yaml | grep "port:"

# Check container images
grep "image:" /tmp/new-output.yaml
```

Expected:
- PVC: storage: 100Gi
- Service: port: 8080
- Images: kiwix-serve:latest and kiwix-downloader:latest

---

## Task 10: Test Different Configuration Scenarios

**Files:**
- Create: `/tmp/test-values-*.yaml`

**Step 1: Test with ingress enabled**

Create `/tmp/test-values-ingress.yaml`:
```yaml
ingress:
  enabled: true
  host: test.example.com
```

Run:
```bash
helm template kiwix . -f /tmp/test-values-ingress.yaml | grep -A 10 "kind: Ingress"
```

Expected: Ingress resource with host test.example.com

**Step 2: Test with route enabled**

Create `/tmp/test-values-route.yaml`:
```yaml
route:
  enabled: true
  gateway:
    name: my-gateway
    namespace: gateway-system
  hostname: route.example.com
```

Run:
```bash
helm template kiwix . -f /tmp/test-values-route.yaml | grep -A 10 "kind: HTTPRoute"
```

Expected: HTTPRoute resource with gateway reference and hostname

**Step 3: Test with cronjob schedule**

Create `/tmp/test-values-cronjob.yaml`:
```yaml
downloader:
  schedule: "0 2 * * 0"
```

Run:
```bash
helm template kiwix . -f /tmp/test-values-cronjob.yaml | grep -A 5 "kind: CronJob"
```

Expected: CronJob resource with schedule "0 2 * * 0"

**Step 4: Test with custom storage**

Create `/tmp/test-values-storage.yaml`:
```yaml
persistence:
  size: 500Gi
  storageClass: fast-ssd
```

Run:
```bash
helm template kiwix . -f /tmp/test-values-storage.yaml | grep -A 10 "PersistentVolumeClaim" | grep -E "(storage:|storageClassName:)"
```

Expected:
- storage: 500Gi
- storageClassName: fast-ssd

**Step 5: Commit test verification**

```bash
git add /tmp/test-values-*.yaml
git commit -m "test: verify hybrid flat values work with various configurations"
```

---

## Task 11: Lint and Validate

**Files:**
- Read: All template files

**Step 1: Run helm lint**

Run:
```bash
helm lint .
```

Expected: No errors, chart passes linting

**Step 2: Validate template output is valid YAML**

Run:
```bash
helm template kiwix . | kubectl apply --dry-run=client -f - 2>&1 | head -20
```

Expected: All resources validate successfully (even without cluster access, schema validation should pass)

**Step 3: Check for required bjw-s fields**

Run:
```bash
helm template kiwix . | grep -E "(controllers:|service:|persistence:)" | wc -l
```

Expected: Should find 3 occurrences (one per top-level key)

---

## Task 12: Update Documentation

**Files:**
- Modify: `README.md`
- Create: `docs/VALUES.md`

**Step 1: Create values documentation**

Create `docs/VALUES.md`:

```markdown
# Values Documentation

## Overview

This chart uses a **hybrid flat** values structure that simplifies configuration while maintaining compatibility with [bjw-s common library](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common) v4.4.0.

## Structure Philosophy

- **2-3 nesting levels maximum** (instead of 5+)
- **Single source of truth** for each configuration
- **Application-focused keys** at top level
- **Templates handle bjw-s mapping** behind the scenes

## Configuration Reference

### Application Images

```yaml
images:
  kiwix:
    repository: ghcr.io/kiwix/kiwix-serve
    tag: latest
    pullPolicy: IfNotPresent
  downloader:
    repository: ghcr.io/jacaudi/kiwix-downloader
    tag: latest
    pullPolicy: IfNotPresent
```

### ZIM Files

```yaml
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim
    sha256: null  # Optional SHA256 checksum for verification
```

### Downloader Configuration

```yaml
downloader:
  enabled: true
  schedule: ""  # Empty = run once as Job
                # Cron format = run as CronJob (e.g., "0 2 * * 0" = weekly)
  resources: {}  # Optional resource limits/requests
```

### Kiwix Application

```yaml
kiwix:
  strategy: Recreate  # Deployment strategy
  args:
    - /data/*.zim  # Command arguments
  resources: {}  # Optional resource limits/requests
  probes:
    liveness:
      enabled: true
      path: /
      port: 8080
    readiness:
      enabled: true
      path: /
      port: 8080
```

### Service

```yaml
service:
  port: 8080  # Service port for kiwix-serve
```

### Storage

```yaml
persistence:
  size: 100Gi
  storageClass: ""  # Empty = cluster default
  accessMode: ReadWriteOnce
  retain: true  # Retain PVC on helm uninstall
```

### Ingress

```yaml
ingress:
  enabled: false
  host: kiwix.local
  path: /
  pathType: Prefix
```

### Gateway API Route

```yaml
route:
  enabled: false
  kind: HTTPRoute  # HTTPRoute, GRPCRoute, TCPRoute, UDPRoute
  gateway:
    name: ""  # Gateway name (required if enabled)
    namespace: ""  # Gateway namespace (required if enabled)
  hostname: kiwix.local
```

### Security

```yaml
security:
  fsGroup: 1000
  fsGroupChangePolicy: "OnRootMismatch"
```

## Examples

### Minimal Production Configuration

```yaml
images:
  kiwix:
    tag: "3.3.0"  # Pin to specific version
  downloader:
    tag: "v1.0.0"

persistence:
  size: 500Gi
  storageClass: fast-ssd

ingress:
  enabled: true
  host: wiki.example.com

downloader:
  enabled: true
  schedule: "0 2 * * 0"  # Weekly updates
```

### Development Configuration

```yaml
persistence:
  size: 10Gi

ingress:
  enabled: true
  host: kiwix.local

downloader:
  enabled: false  # Manual ZIM file management
```

### High Availability Configuration

```yaml
kiwix:
  resources:
    requests:
      memory: "4Gi"
      cpu: "2"
    limits:
      memory: "8Gi"
      cpu: "4"

persistence:
  size: 1Ti
  storageClass: fast-ssd
  accessMode: ReadWriteMany  # If supported by storage class

ingress:
  enabled: true
  host: wiki.example.com
```
```

**Step 2: Update README.md**

Add to README.md after installation section:

```markdown
## Configuration

See [docs/VALUES.md](docs/VALUES.md) for complete values documentation.

### Quick Start Values

```yaml
# Minimal configuration
persistence:
  size: 100Gi

ingress:
  enabled: true
  host: kiwix.local
```

For production deployments, see [docs/VALUES.md](docs/VALUES.md) for examples.
```

**Step 3: Commit documentation**

```bash
git add README.md docs/VALUES.md
git commit -m "docs: add comprehensive values documentation for hybrid flat structure"
```

---

## Task 13: Clean Up

**Files:**
- Delete: `values.yaml.backup`
- Delete: `docs/baseline-output.yaml`
- Delete: `/tmp/test-values-*.yaml`
- Delete: `/tmp/new-output.yaml`

**Step 1: Remove temporary files**

Run:
```bash
rm -f values.yaml.backup docs/baseline-output.yaml /tmp/test-values-*.yaml /tmp/new-output.yaml
```

Expected: Files removed

**Step 2: Final verification**

Run:
```bash
helm lint .
helm template kiwix . > /dev/null
echo "Success! Chart is ready."
```

Expected: No errors, confirmation message

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore: clean up temporary refactor files"
```

---

## Task 14: Version Bump

**Files:**
- Modify: `Chart.yaml`

**Step 1: Update chart version**

Edit `Chart.yaml`, increment minor version (breaking change to values):
```yaml
version: 0.3.0  # Was 0.2.0
```

**Step 2: Commit version bump**

```bash
git add Chart.yaml
git commit -m "chore: bump version to 0.3.0 for hybrid flat values refactor"
```

---

## Completion Checklist

- [ ] Baseline captured
- [ ] New values.yaml created
- [ ] Helper templates created (6 files)
- [ ] common.yaml integrated helpers
- [ ] Output comparison shows functional equivalence
- [ ] Configuration scenarios tested
- [ ] Lint passes
- [ ] Documentation complete
- [ ] Cleanup done
- [ ] Version bumped

## Notes

- **Breaking change**: Existing values.yaml files will need migration
- **Migration path**: Users can reference `values.yaml.backup` or docs/VALUES.md
- **Backward compatibility**: None - this is a major refactor
- **bjw-s compatibility**: Full compatibility maintained with v4.4.0
