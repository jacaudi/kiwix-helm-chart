# Kiwix Helm Chart Design

**Date:** 2025-11-05
**Status:** Approved

## Overview

A Helm chart for deploying `ghcr.io/kiwix/kiwix-serve` using the bjw-s app-template common library as a base. The chart provides a declarative way to manage ZIM file downloads and serve offline content via Kiwix.

## Goals

- **Scope**: Both personal use and eventual public distribution
- **Key Feature**: Pass a list of ZIM file URLs as values, automatically download and serve them
- **Flexibility**: Support both one-time downloads and periodic updates
- **Maintainability**: Clean separation between downloader and server components

## Architecture

### High-Level Design

The chart uses **two controllers** with a standalone downloader pattern:

1. **Downloader Controller**: Job or CronJob that downloads ZIM files to shared storage
2. **Main Controller**: Deployment running kiwix-serve to serve the downloaded files
3. **Shared Storage**: Single ReadWriteOnce PVC mounted to both controllers
4. **ConfigMap**: Generated from user-provided URL list

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

### Benefits of Standalone Pattern

- Clean component separation
- Independent lifecycle management
- Downloader logic updates don't affect kiwix-serve
- CronJob can be disabled for static deployments
- Each component scales/configures independently

## Components

### 1. Chart Structure

```
kiwix-helm-chart/
├── Chart.yaml                 # Dependencies: bjw-s/app-template: 4.x
├── values.yaml                # Default configuration
├── values.schema.json         # JSON schema validation (optional)
├── templates/
│   ├── configmap.yaml         # Generated from zimFiles list
│   └── _helpers.tpl           # Custom template functions
├── .github/workflows/
│   ├── docker.yaml           # Build downloader image
│   └── chart.yaml            # Package and publish chart
├── docker/
│   ├── Dockerfile            # Downloader container
│   └── downloader.sh         # Download script
└── README.md                  # Installation and usage docs
```

### 2. Values Schema

**Key configuration sections:**

```yaml
# ZIM files to download
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim
    sha256: abc123...  # Optional checksum

# Downloader controller
downloader:
  enabled: true
  schedule: "0 2 * * 0"  # Empty = Job, set = CronJob
  image:
    repository: ghcr.io/[owner]/kiwix-downloader
    tag: latest
  resources: {}

# Kiwix-serve controller
controllers:
  main:
    containers:
      main:
        image:
          repository: ghcr.io/kiwix/kiwix-serve
          tag: latest

# Shared persistence
persistence:
  data:
    enabled: true
    type: persistentVolumeClaim
    accessMode: ReadWriteOnce
    size: 100Gi              # Configurable
    storageClass: ""         # Empty = cluster default, configurable
    retain: true
    globalMounts:
      - path: /data
```

### 3. Downloader Container

**Dockerfile** (`docker/Dockerfile`):
- Base: Alpine 3.19
- Tools: curl, bash, jq, coreutils
- Entrypoint: `/usr/local/bin/downloader.sh`

**Download Script Features** (`docker/downloader.sh`):
- Reads ConfigMap at `/config/zim-urls.json`
- curl with retry logic (3 attempts, exponential backoff)
- SHA256 checksum verification (if provided)
- **Keeps all existing files** - accumulates over time
- Idempotent - safe to run multiple times
- Skips files that already exist with valid checksum
- Logs progress and errors
- Exit 0 on success, non-zero on failure

**ConfigMap Format:**
```json
{
  "files": [
    {"url": "https://...", "sha256": "abc123..."},
    {"url": "https://...", "sha256": null}
  ]
}
```

### 4. Helm Templates

**ConfigMap Template** (`templates/configmap.yaml`):
- Generates JSON from `zimFiles` list
- Includes URLs and optional checksums
- Only mounted to downloader controller

**Controller Configuration:**
- **Downloader**: Type determined by `schedule` value (Job vs CronJob)
- **Main**: Standard Deployment with kiwix-serve
- **Persistence**: Shared PVC with configurable size and storage class
- **Service**: Exposes kiwix-serve on port 8080

### 5. CI/CD with GitHub Actions

**Container Image Workflow** (`.github/workflows/docker.yaml`):
- **Triggers**: Push to main, git tags (v*)
- **Builds**: Multi-arch (amd64, arm64) using Docker buildx
- **Registry**: ghcr.io
- **Tags**:
  - `latest` - main branch
  - `v1.0.0`, `v1.2.3` - git tags (keeps 'v' prefix)

**Helm Chart Workflow** (`.github/workflows/chart.yaml`):
- **Triggers**: Git tags (v*) only
- **Steps**:
  1. `helm lint` - validate chart
  2. `helm template` - test rendering
  3. `helm package` - create archive
  4. Push to `oci://ghcr.io/[owner]/charts/kiwix`
- **Versioning**: Chart.yaml version = `1.0.0` (no 'v'), appVersion = `v1.0.0` (with 'v')

**No PR-based tags** - simpler release process

## Configuration

### Storage Configuration

Users can specify:
- **Size**: Default 100Gi, configurable for different use cases
- **StorageClass**: Empty string uses cluster default, or specify (ceph-block, local-path, etc.)

Examples:
```yaml
# Ceph RBD
persistence:
  data:
    size: 500Gi
    storageClass: ceph-block

# Local testing
persistence:
  data:
    size: 10Gi
    storageClass: local-path
```

### Download Modes

1. **One-time (Job)**:
   ```yaml
   downloader:
     schedule: ""  # Empty or omit
   ```

2. **Periodic Updates (CronJob)**:
   ```yaml
   downloader:
     schedule: "0 2 * * 0"  # Weekly Sunday 2am
   ```

### File Management Strategy

**Keep all files** - accumulates over time:
- Good for maintaining historical snapshots
- Requires larger PVC
- No automatic cleanup
- Users manually delete old files if needed

## Installation

### From OCI Registry

```bash
# Login to GHCR (if private)
helm registry login ghcr.io

# Install
helm install my-kiwix oci://ghcr.io/[owner]/charts/kiwix \
  --version v1.0.0 \
  --namespace kiwix \
  --create-namespace \
  --values values.yaml
```

### Custom Values

```yaml
zimFiles:
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-10.zim
  - url: https://download.kiwix.org/zim/wikipedia_en_100_2025-09.zim

downloader:
  schedule: "0 2 * * 0"

persistence:
  data:
    size: 200Gi
    storageClass: ceph-block
```

## Testing and Validation

### Local Development

```bash
# Lint
helm lint .

# Template and inspect
helm template kiwix . -f values.yaml > output.yaml

# Install locally
helm install kiwix . --namespace kiwix --create-namespace

# Upgrade test
helm upgrade kiwix . --namespace kiwix
```

### Validation Checklist

1. **Chart structure**: `helm lint` passes
2. **ConfigMap generation**: Valid JSON, correct URLs
3. **Downloader execution**: Job/CronJob completes successfully
4. **File verification**: ZIM files present in `/data`
5. **Kiwix-serve**: Service accessible, content served
6. **Upgrades**: New URLs download incrementally

### Operational Considerations

- **Monitoring**: Track Job success/failure, PVC usage
- **Troubleshooting**: Check downloader logs (`kubectl logs job/kiwix-downloader`)
- **Storage growth**: Monitor accumulating files
- **Initial download**: Large files may take hours, set appropriate Job timeout

## Documentation

**Includes:**
- README.md with quick start
- Configuration examples
- values.yaml with inline comments
- Troubleshooting guide

## Decisions and Rationale

| Decision | Rationale |
|----------|-----------|
| **Standalone downloader** | Clean separation, independent lifecycle, easier maintenance |
| **Custom downloader image** | Robust retry/checksum logic, better than shell scripts |
| **Keep all files** | Archive/history use case, simpler logic than retention policy |
| **Single RWO PVC** | Simple deployment model, compatible with most storage classes |
| **Configurable download mode** | Flexibility for static vs dynamic deployments |
| **bjw-s app-template** | Popular common library, reduces boilerplate |
| **OCI format for chart** | Modern standard, GHCR integration |
| **No PR tags** | Cleaner release process, tags are source of truth |

## Future Enhancements

Potential features for later versions:
- Retention policy (keep last N versions)
- Parallel downloads
- Download progress metrics/dashboard
- ReadWriteMany support for multi-pod scenarios
- Automatic cleanup of corrupted files
- Bandwidth limiting
