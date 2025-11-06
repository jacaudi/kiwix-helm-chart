# Gateway API Routes

This chart supports Kubernetes Gateway API routes as an alternative to traditional Ingress resources. Routes provide more advanced routing capabilities and are becoming the standard for ingress traffic management in Kubernetes.

## Prerequisites

Gateway API CRDs must be installed in your cluster:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

You also need a Gateway API-compatible ingress controller (e.g., Istio, Envoy Gateway, Kong, etc.) and a Gateway resource configured.

## Configuration

Routes are configured in `values.yaml` under the `route` key, similar to ingress configuration.

### HTTPRoute Example

```yaml
route:
  main:
    enabled: true
    kind: HTTPRoute
    parentRefs:
      - name: my-gateway       # Gateway name
        namespace: default      # Gateway namespace
    hostnames:
      - kiwix.example.com
    rules:
      - backendRefs:
          - identifier: main    # References service.main
        matches:
          - path:
              type: PathPrefix
              value: /
```

### GRPCRoute Example

For gRPC services:

```yaml
route:
  main:
    enabled: true
    kind: GRPCRoute
    parentRefs:
      - name: my-gateway
        namespace: default
    hostnames:
      - grpc.example.com
    rules:
      - backendRefs:
          - identifier: main
        matches:
          - method:
              service: MyService
              method: MyMethod
```

### TCPRoute Example

For TCP services (no hostname matching):

```yaml
route:
  main:
    enabled: true
    kind: TCPRoute
    parentRefs:
      - name: my-gateway
        namespace: default
    rules:
      - backendRefs:
          - identifier: main
```

### UDPRoute Example

For UDP services:

```yaml
route:
  main:
    enabled: true
    kind: UDPRoute
    parentRefs:
      - name: my-gateway
        namespace: default
    rules:
      - backendRefs:
          - identifier: main
```

## Advanced Configuration

### Multiple Backend Services

Route traffic to multiple services with weights:

```yaml
route:
  main:
    enabled: true
    kind: HTTPRoute
    parentRefs:
      - name: my-gateway
        namespace: default
    hostnames:
      - kiwix.example.com
    rules:
      - backendRefs:
          - identifier: main
            weight: 90
          - name: kiwix-canary-service  # External service
            port: 8080
            weight: 10
```

### Request Filtering

Modify headers, redirect requests, etc.:

```yaml
route:
  main:
    enabled: true
    kind: HTTPRoute
    parentRefs:
      - name: my-gateway
        namespace: default
    hostnames:
      - kiwix.example.com
    rules:
      - backendRefs:
          - identifier: main
        matches:
          - path:
              type: PathPrefix
              value: /api
        filters:
          - type: RequestHeaderModifier
            requestHeaderModifier:
              add:
                - name: X-Custom-Header
                  value: custom-value
              remove:
                - X-Internal-Header
```

### Path-Based Routing

Route different paths to different services:

```yaml
route:
  api:
    enabled: true
    kind: HTTPRoute
    parentRefs:
      - name: my-gateway
        namespace: default
    hostnames:
      - kiwix.example.com
    rules:
      - matches:
          - path:
              type: PathPrefix
              value: /api
        backendRefs:
          - name: api-service
            port: 8080
      - matches:
          - path:
              type: PathPrefix
              value: /
        backendRefs:
          - identifier: main
```

### Gateway Listener Selection

Target specific Gateway listeners:

```yaml
route:
  main:
    enabled: true
    kind: HTTPRoute
    parentRefs:
      - name: my-gateway
        namespace: default
        sectionName: https-listener  # Target specific listener
    hostnames:
      - kiwix.example.com
    rules:
      - backendRefs:
          - identifier: main
```

## Multiple Routes

You can define multiple routes for different purposes:

```yaml
route:
  http:
    enabled: true
    kind: HTTPRoute
    parentRefs:
      - name: external-gateway
        namespace: gateway-system
    hostnames:
      - kiwix.example.com
    rules:
      - backendRefs:
          - identifier: main

  internal:
    enabled: true
    kind: HTTPRoute
    parentRefs:
      - name: internal-gateway
        namespace: gateway-system
    hostnames:
      - kiwix.internal.local
    rules:
      - backendRefs:
          - identifier: main
```

## Route vs Ingress

| Feature | Ingress | Gateway API Routes |
|---------|---------|-------------------|
| Standard | Kubernetes core | Gateway API (evolving standard) |
| Expressiveness | Basic | Advanced |
| Protocol support | HTTP/HTTPS | HTTP, HTTPS, gRPC, TCP, UDP |
| Traffic splitting | Limited | Native support |
| Header manipulation | Controller-dependent | Standardized |
| Multi-controller | Limited | Better support |

## Troubleshooting

### Route not working

1. **Check Gateway API CRDs are installed:**
   ```bash
   kubectl get crd gateways.gateway.networking.k8s.io
   kubectl get crd httproutes.gateway.networking.k8s.io
   ```

2. **Verify Gateway exists:**
   ```bash
   kubectl get gateway -n <gateway-namespace>
   ```

3. **Check Route status:**
   ```bash
   kubectl describe httproute -n <namespace> <route-name>
   ```

4. **Verify Gateway controller is running:**
   ```bash
   kubectl get pods -n <gateway-controller-namespace>
   ```

### Port resolution issues

If the port isn't auto-detected correctly, specify it explicitly:

```yaml
route:
  main:
    rules:
      - backendRefs:
          - identifier: main
            port: 8080  # Explicit port number
```

## References

- [Kubernetes Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Gateway API Implementations](https://gateway-api.sigs.k8s.io/implementations/)
- [HTTPRoute Specification](https://gateway-api.sigs.k8s.io/references/spec/#gateway.networking.k8s.io/v1.HTTPRoute)
- [bjw-s Common Library](https://github.com/bjw-s-labs/helm-charts/)
