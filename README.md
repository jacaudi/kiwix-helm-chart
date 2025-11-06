# Kiwix Helm Chart

Helm chart for deploying [kiwix-serve](https://github.com/kiwix/kiwix-tools) with automated ZIM file downloads.

## Features

- 🚀 Automated ZIM file downloads with retry logic and checksum verification
- 🔄 One-time or periodic download modes (Job or CronJob)
- 📦 OCI-based Helm chart distribution via GHCR
- 🛡️ Built on [bjw-s common library](https://github.com/bjw-s-labs/helm-charts)
- 💾 Persistent storage with configurable size and storage class
- 🎯 Keep-all file management strategy for archival use cases
- 🔄 Automated dependency updates with Renovate

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

## Automated Dependency Updates

This project uses [Renovate](https://github.com/renovatebot/renovate) to automatically keep dependencies up-to-date:

- **GitHub Actions**: Auto-updated to latest versions
- **Docker base images**: Tracks Alpine Linux releases
- **Helm dependencies**: Monitors bjw-s common library updates
- **Container images**: Tracks kiwix-serve and downloader versions

**Schedule:** Daily at 2am UTC

**Auto-merge policy:** Patch updates (1.0.x) automatically merge after 3 days if CI passes.

**Dependency Dashboard:** Check the [Dependency Dashboard](../../issues) issue for pending updates.

### Manual Renovate Run

Trigger Renovate manually via GitHub Actions:
```bash
gh workflow run renovate.yaml
```

Or via GitHub UI: Actions → Renovate → Run workflow

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
cd image
docker build -t ghcr.io/jacaudi/kiwix-downloader:test .
docker push ghcr.io/jacaudi/kiwix-downloader:test
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