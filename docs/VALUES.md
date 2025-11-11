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
