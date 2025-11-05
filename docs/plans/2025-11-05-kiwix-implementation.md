# Kiwix Helm Chart Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Helm chart for deploying kiwix-serve with automated ZIM file downloads using bjw-s app-template as base.

**Architecture:** Standalone downloader pattern with two controllers (downloader Job/CronJob + kiwix-serve Deployment) sharing a PVC. ConfigMap generated from URL list, custom downloader image with retry/checksum logic. GitHub Actions publishes both chart and container to GHCR in OCI format.

**Tech Stack:** Helm 3, bjw-s app-template 4.x, Alpine Linux, curl, GitHub Actions, GHCR (OCI registry)

---

## Task 1: Chart Foundation

**Files:**
- Create: `Chart.yaml`
- Create: `values.yaml`
- Create: `templates/_helpers.tpl`

### Step 1: Create Chart.yaml with bjw-s dependency

Create `Chart.yaml`:

```yaml
apiVersion: v2
name: kiwix
description: Helm chart for deploying kiwix-serve with automated ZIM file downloads
type: application
version: 0.1.0
appVersion: "latest"
maintainers:
  - name: jacaudi
dependencies:
  - name: app-template
    version: 4.x.x
    repository: https://bjw-s-labs.github.io/helm-charts
```

### Step 2: Create initial values.yaml

Create `values.yaml`:

```yaml
# ZIM files to download
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim
    sha256: null

# Downloader controller configuration
downloader:
  enabled: true
  schedule: ""  # Empty = Job, set = CronJob (e.g., "0 2 * * 0")
  image:
    repository: ghcr.io/jacaudi/kiwix-downloader
    tag: latest
    pullPolicy: IfNotPresent
  resources: {}

# Kiwix-serve controller
controllers:
  main:
    strategy: Recreate
    containers:
      main:
        image:
          repository: ghcr.io/kiwix/kiwix-serve
          tag: latest
          pullPolicy: IfNotPresent
        args:
          - --port=8080
          - /data/*.zim
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /
                port: 8080
          readiness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /
                port: 8080

  downloader:
    enabled: true
    type: job
    containers:
      main:
        image:
          repository: "{{ .Values.downloader.image.repository }}"
          tag: "{{ .Values.downloader.image.tag }}"
          pullPolicy: "{{ .Values.downloader.image.pullPolicy }}"

# Service configuration
service:
  main:
    controller: main
    ports:
      http:
        port: 8080

# Ingress configuration (disabled by default)
ingress:
  main:
    enabled: false
    hosts:
      - host: kiwix.local
        paths:
          - path: /
            pathType: Prefix
            service:
              identifier: main
              port: http

# Shared persistence
persistence:
  data:
    enabled: true
    type: persistentVolumeClaim
    accessMode: ReadWriteOnce
    size: 100Gi
    storageClass: ""
    retain: true
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
```

### Step 3: Create helper template file

Create `templates/_helpers.tpl`:

```yaml
{{/* vim: set filetype=mustache: */}}
{{/*
Return the full name for the chart
*/}}
{{- define "kiwix.fullname" -}}
{{- include "bjw-s.common.lib.chart.names.fullname" . -}}
{{- end -}}
```

### Step 4: Verify chart structure

Run: `helm lint .`
Expected: No errors

### Step 5: Commit

```bash
git add Chart.yaml values.yaml templates/_helpers.tpl
git commit -m "feat: add chart foundation with bjw-s dependency

- Chart.yaml with app-template dependency
- Initial values.yaml with controllers and persistence
- Helper templates for naming
"
```

---

## Task 2: ConfigMap Template

**Files:**
- Create: `templates/configmap.yaml`

### Step 1: Create ConfigMap template for ZIM URLs

Create `templates/configmap.yaml`:

```yaml
{{- if .Values.zimFiles }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "kiwix.fullname" . }}-zim-urls
  labels:
    {{- include "bjw-s.common.lib.metadata.allLabels" $ | nindent 4 }}
data:
  zim-urls.json: |
    {
      "files": [
        {{- range $i, $file := .Values.zimFiles }}
        {{- if $i }},{{ end }}
        {
          "url": {{ $file.url | quote }},
          "sha256": {{ $file.sha256 | default "null" }}
        }
        {{- end }}
      ]
    }
{{- end }}
```

### Step 2: Test ConfigMap rendering

Run: `helm template test . --show-only templates/configmap.yaml`
Expected: Valid ConfigMap with JSON data containing zimFiles

### Step 3: Commit

```bash
git add templates/configmap.yaml
git commit -m "feat: add ConfigMap template for ZIM file URLs

Generates JSON config from zimFiles list for downloader container
"
```

---

## Task 3: Downloader Container - Dockerfile

**Files:**
- Create: `docker/Dockerfile`

### Step 1: Create Dockerfile

Create `docker/Dockerfile`:

```dockerfile
FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    coreutils

# Copy download script
COPY downloader.sh /usr/local/bin/downloader.sh
RUN chmod +x /usr/local/bin/downloader.sh

# Set working directory
WORKDIR /data

# Run download script
ENTRYPOINT ["/usr/local/bin/downloader.sh"]
```

### Step 2: Verify Dockerfile syntax

Run: `docker build --no-cache -f docker/Dockerfile -t test docker/ || echo "Expected to fail - downloader.sh not created yet"`
Expected: Fails with "COPY failed" (downloader.sh doesn't exist yet)

### Step 3: Commit

```bash
git add docker/Dockerfile
git commit -m "feat: add downloader Dockerfile

Alpine-based image with curl, jq, and bash for ZIM downloads
"
```

---

## Task 4: Downloader Container - Download Script

**Files:**
- Create: `docker/downloader.sh`

### Step 1: Create download script with retry logic

Create `docker/downloader.sh`:

```bash
#!/bin/bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/config/zim-urls.json}"
DATA_DIR="${DATA_DIR:-/data}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-10}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    log "ERROR: $*" >&2
}

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Parse config file
if ! FILE_COUNT=$(jq -r '.files | length' "$CONFIG_FILE"); then
    error "Failed to parse config file"
    exit 1
fi

log "Found $FILE_COUNT file(s) to process"

# Process each file
for i in $(seq 0 $((FILE_COUNT - 1))); do
    URL=$(jq -r ".files[$i].url" "$CONFIG_FILE")
    CHECKSUM=$(jq -r ".files[$i].sha256" "$CONFIG_FILE")
    FILENAME=$(basename "$URL")
    FILEPATH="$DATA_DIR/$FILENAME"

    log "Processing ($((i + 1))/$FILE_COUNT): $FILENAME"

    # Check if file already exists with valid checksum
    if [[ -f "$FILEPATH" ]] && [[ "$CHECKSUM" != "null" ]]; then
        log "File exists, verifying checksum..."
        if echo "$CHECKSUM  $FILEPATH" | sha256sum -c -s; then
            log "Checksum valid, skipping download"
            continue
        else
            log "Checksum mismatch, re-downloading"
            rm -f "$FILEPATH"
        fi
    elif [[ -f "$FILEPATH" ]]; then
        log "File exists and no checksum provided, skipping"
        continue
    fi

    # Download with retry logic
    ATTEMPT=1
    SUCCESS=false

    while [[ $ATTEMPT -le $MAX_RETRIES ]]; do
        log "Download attempt $ATTEMPT/$MAX_RETRIES: $URL"

        if curl -L -f -S --progress-bar -o "$FILEPATH" "$URL"; then
            SUCCESS=true
            break
        else
            error "Download failed (attempt $ATTEMPT/$MAX_RETRIES)"
            rm -f "$FILEPATH"

            if [[ $ATTEMPT -lt $MAX_RETRIES ]]; then
                DELAY=$((RETRY_DELAY * ATTEMPT))
                log "Retrying in ${DELAY}s..."
                sleep "$DELAY"
            fi
        fi

        ATTEMPT=$((ATTEMPT + 1))
    done

    if [[ "$SUCCESS" == "false" ]]; then
        error "Failed to download $FILENAME after $MAX_RETRIES attempts"
        exit 1
    fi

    # Verify checksum if provided
    if [[ "$CHECKSUM" != "null" ]]; then
        log "Verifying checksum..."
        if echo "$CHECKSUM  $FILEPATH" | sha256sum -c -s; then
            log "Checksum verified successfully"
        else
            error "Checksum verification failed for $FILENAME"
            rm -f "$FILEPATH"
            exit 1
        fi
    fi

    log "Successfully downloaded: $FILENAME ($(du -h "$FILEPATH" | cut -f1))"
done

log "All downloads completed successfully"
exit 0
```

### Step 2: Make script executable

Run: `chmod +x docker/downloader.sh`

### Step 3: Verify script syntax

Run: `bash -n docker/downloader.sh`
Expected: No output (syntax valid)

### Step 4: Commit

```bash
git add docker/downloader.sh
git commit -m "feat: add downloader script with retry and checksum logic

Features:
- Reads JSON config from /config/zim-urls.json
- Downloads to /data with curl retry logic
- SHA256 checksum verification
- Idempotent (skips existing files with valid checksums)
- Configurable via environment variables
"
```

---

## Task 5: GitHub Actions - Docker Workflow

**Files:**
- Create: `.github/workflows/docker.yaml`

### Step 1: Create Docker build workflow

Create `.github/workflows/docker.yaml`:

```yaml
name: Build and Push Docker Image

on:
  push:
    branches:
      - main
    tags:
      - 'v*'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/kiwix-downloader

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=tag
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./docker
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Step 2: Verify workflow syntax

Run: `cat .github/workflows/docker.yaml | grep -q "name: Build and Push Docker Image" && echo "OK"`
Expected: OK

### Step 3: Commit

```bash
git add .github/workflows/docker.yaml
git commit -m "feat: add GitHub Actions workflow for Docker image

Builds multi-arch image (amd64, arm64) and pushes to GHCR
Tags: latest (main branch), v* (git tags)
"
```

---

## Task 6: GitHub Actions - Helm Chart Workflow

**Files:**
- Create: `.github/workflows/chart.yaml`

### Step 1: Create Helm chart workflow

Create `.github/workflows/chart.yaml`:

```yaml
name: Package and Push Helm Chart

on:
  push:
    tags:
      - 'v*'

env:
  REGISTRY: ghcr.io
  CHART_NAME: kiwix

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Helm
        uses: azure/setup-helm@v4
        with:
          version: 'latest'

      - name: Extract version from tag
        id: version
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          echo "version=$VERSION" >> $GITHUB_OUTPUT
          echo "tag=${GITHUB_REF#refs/tags/}" >> $GITHUB_OUTPUT

      - name: Update Chart.yaml version
        run: |
          sed -i "s/^version:.*/version: ${{ steps.version.outputs.version }}/" Chart.yaml
          sed -i "s/^appVersion:.*/appVersion: \"${{ steps.version.outputs.tag }}\"/" Chart.yaml

      - name: Update dependencies
        run: helm dependency update

      - name: Lint chart
        run: helm lint .

      - name: Template chart
        run: helm template test . > /dev/null

      - name: Package chart
        run: helm package .

      - name: Log in to GitHub Container Registry
        run: |
          echo ${{ secrets.GITHUB_TOKEN }} | helm registry login ${{ env.REGISTRY }} -u ${{ github.actor }} --password-stdin

      - name: Push chart to GHCR
        run: |
          helm push ${{ env.CHART_NAME }}-${{ steps.version.outputs.version }}.tgz oci://${{ env.REGISTRY }}/${{ github.repository_owner }}/charts
```

### Step 2: Verify workflow syntax

Run: `cat .github/workflows/chart.yaml | grep -q "name: Package and Push Helm Chart" && echo "OK"`
Expected: OK

### Step 3: Commit

```bash
git add .github/workflows/chart.yaml
git commit -m "feat: add GitHub Actions workflow for Helm chart

Packages chart and pushes to GHCR as OCI artifact
Triggers on git tags (v*)
Updates Chart.yaml versions from tag
"
```

---

## Task 7: Documentation - README

**Files:**
- Create: `README.md`

### Step 1: Create comprehensive README

Create `README.md`:

```markdown
# Kiwix Helm Chart

Helm chart for deploying [kiwix-serve](https://github.com/kiwix/kiwix-tools) with automated ZIM file downloads.

## Features

- 🚀 Automated ZIM file downloads with retry logic and checksum verification
- 🔄 One-time or periodic download modes (Job or CronJob)
- 📦 OCI-based Helm chart distribution via GHCR
- 🛡️ Built on [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts) common library
- 💾 Persistent storage with configurable size and storage class
- 🎯 Keep-all file management strategy for archival use cases

## Prerequisites

- Kubernetes 1.19+
- Helm 3.8+
- Persistent Volume provisioner (for PVC support)

## Installation

### Install from OCI Registry

```bash
# Login to GHCR (if repository is private)
helm registry login ghcr.io -u <username>

# Install chart
helm install my-kiwix oci://ghcr.io/jacaudi/charts/kiwix \
  --version v0.1.0 \
  --namespace kiwix \
  --create-namespace \
  --values values.yaml
```

### Install from Source

```bash
# Clone repository
git clone https://github.com/jacaudi/kiwix-helm-chart.git
cd kiwix-helm-chart

# Update dependencies
helm dependency update

# Install
helm install my-kiwix . \
  --namespace kiwix \
  --create-namespace \
  --values values.yaml
```

## Configuration

### Basic Example

```yaml
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-09.zim

persistence:
  data:
    size: 50Gi
```

### Periodic Updates (CronJob)

```yaml
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim

downloader:
  schedule: "0 2 * * 0"  # Weekly on Sunday at 2am

persistence:
  data:
    size: 200Gi
    storageClass: ceph-block
```

### With Checksum Verification

```yaml
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim
    sha256: abc123def456...
```

### Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `zimFiles` | List of ZIM file URLs to download | `[]` |
| `zimFiles[].url` | URL of ZIM file | Required |
| `zimFiles[].sha256` | SHA256 checksum (optional) | `null` |
| `downloader.enabled` | Enable downloader controller | `true` |
| `downloader.schedule` | CronJob schedule (empty = Job) | `""` |
| `downloader.image.repository` | Downloader image repository | `ghcr.io/jacaudi/kiwix-downloader` |
| `downloader.image.tag` | Downloader image tag | `latest` |
| `persistence.data.size` | PVC size | `100Gi` |
| `persistence.data.storageClass` | Storage class name | `""` (cluster default) |
| `service.main.ports.http.port` | HTTP service port | `8080` |
| `ingress.main.enabled` | Enable ingress | `false` |

See `values.yaml` for complete configuration options.

## Architecture

The chart uses a standalone downloader pattern with two controllers:

1. **Downloader Controller**: Job (one-time) or CronJob (periodic) that downloads ZIM files to shared storage
2. **Main Controller**: Deployment running kiwix-serve that serves the downloaded files

Both controllers share a PVC mounted at `/data`. The downloader reads URLs from a ConfigMap generated from `zimFiles`.

```
User provides zimFiles list
        ↓
    ConfigMap (zim-urls.json)
        ↓
    Downloader (Job/CronJob)
        ↓
    PVC (/data)
        ↓
    Kiwix-serve (Deployment)
```

## Storage Considerations

ZIM files can be large (100MB - 100GB). The chart uses a **keep-all** strategy, accumulating files over time.

**Recommended PVC sizes:**
- Small demo (1-2 files): 10-50 Gi
- Medium archive (5-10 files): 100-200 Gi
- Large archive (20+ files): 500+ Gi

Monitor PVC usage over time, especially when using periodic updates.

## Troubleshooting

### Check Downloader Logs

```bash
# For Job
kubectl logs -n kiwix job/my-kiwix-downloader

# For CronJob (get latest job)
kubectl logs -n kiwix $(kubectl get jobs -n kiwix -l app.kubernetes.io/name=kiwix -o name | tail -1)
```

### Verify Downloaded Files

```bash
kubectl exec -n kiwix deployment/my-kiwix -- ls -lh /data
```

### Test Kiwix Service

```bash
# Port-forward
kubectl port-forward -n kiwix svc/my-kiwix 8080:8080

# Access in browser
open http://localhost:8080
```

### Common Issues

**Download timeout**: Increase Job timeout or check network connectivity
```yaml
downloader:
  resources:
    limits:
      cpu: 1000m
      memory: 512Mi
```

**PVC full**: Increase size or manually delete old files
```bash
kubectl exec -n kiwix deployment/my-kiwix -- rm /data/old-file.zim
```

## Development

### Building Downloader Image

```bash
cd docker
docker build -t kiwix-downloader:dev .
docker run -v $(pwd):/data -v $(pwd)/config:/config kiwix-downloader:dev
```

### Testing Chart Locally

```bash
# Lint
helm lint .

# Template
helm template test . --values values.yaml

# Dry-run install
helm install test . --dry-run --debug
```

## License

See repository license.

## Contributing

Contributions welcome! Please open an issue or pull request.
```

### Step 2: Verify README formatting

Run: `grep -q "# Kiwix Helm Chart" README.md && echo "OK"`
Expected: OK

### Step 3: Update root README if different

If root `README.md` exists and is different:
```bash
cp docs/plans/../../../README.md README.md.bak
cat > ../../../README.md << 'EOF'
# Kiwix Helm Chart

Helm chart for deploying kiwix-serve with automated ZIM file downloads.

See full documentation in the worktree: `.worktrees/feature/kiwix-implementation/README.md`
EOF
```

### Step 4: Commit

```bash
git add README.md
git commit -m "docs: add comprehensive README

Installation instructions, configuration examples, architecture
overview, troubleshooting guide, and development setup
"
```

---

## Task 8: Final Validation

**Files:**
- Verify all files created correctly

### Step 1: Update Helm dependencies

Run: `helm dependency update`
Expected: Downloads bjw-s app-template chart to `charts/`

### Step 2: Lint chart

Run: `helm lint .`
Expected: No errors, possibly some warnings about default values

### Step 3: Template chart

Run: `helm template test . > /tmp/kiwix-rendered.yaml`
Expected: Successfully renders all templates

### Step 4: Verify rendered resources

Run: `cat /tmp/kiwix-rendered.yaml | grep -E "kind: (ConfigMap|Deployment|Job|Service|PersistentVolumeClaim)" | wc -l`
Expected: At least 5 resources (ConfigMap, Deployment, Job, Service, PVC)

### Step 5: Test with custom values

Create `/tmp/test-values.yaml`:
```yaml
zimFiles:
  - url: https://example.com/test.zim
    sha256: abc123

downloader:
  schedule: "0 3 * * *"

persistence:
  data:
    size: 50Gi
    storageClass: local-path
```

Run: `helm template test . -f /tmp/test-values.yaml > /tmp/kiwix-custom.yaml`
Expected: Successfully renders with custom values

### Step 6: Verify CronJob creation

Run: `grep -q "kind: CronJob" /tmp/kiwix-custom.yaml && echo "CronJob created"`
Expected: CronJob created (because schedule is set)

### Step 7: Build Docker image locally (optional)

Run: `docker build -t kiwix-downloader:test docker/`
Expected: Successfully builds image

### Step 8: Commit

```bash
git add charts/
git commit -m "chore: add Helm dependencies

Downloaded bjw-s app-template chart
"
```

---

## Verification Checklist

Before marking complete, verify:

- [ ] `helm lint .` passes with no errors
- [ ] `helm template test .` renders successfully
- [ ] ConfigMap contains valid JSON
- [ ] Downloader container builds without errors
- [ ] Job created when `downloader.schedule` is empty
- [ ] CronJob created when `downloader.schedule` is set
- [ ] All GitHub Actions workflows have valid syntax
- [ ] README.md is comprehensive and accurate
- [ ] All files committed with descriptive messages

## Next Steps

After implementation:

1. **Test Installation**: Deploy to a test cluster
2. **Create Release**: Tag `v0.1.0` to trigger GitHub Actions
3. **Verify Publishing**: Check GHCR for chart and image
4. **Documentation**: Update any additional docs as needed
