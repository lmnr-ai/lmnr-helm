# Service Dependencies in Kubernetes

This document explains how service dependencies are managed in this Helm chart and addresses common questions about Kubernetes vs CloudFormation/GitHub Actions.

## Table of Contents

- [The Init Container Solution](#the-init-container-solution)
- [Configuration](#configuration)
- [Dependency Tree](#dependency-tree)

## The Init Container Solution

We ensure services wait for their dependencies before starting.

### How Init Containers Work

Init containers run **before** the main container and must complete successfully:

```yaml
spec:
  initContainers:
    # Wait for Redis to be available
    - name: wait-for-redis
      image: busybox:latest
      command: ['sh', '-c', 'until nc -z redis-service 6379; do echo waiting...; sleep 2; done']

  containers:
    # Main app only starts after init containers succeed
    - name: app
      image: myapp:latest
```

### Two Types of Checks

**TCP Port Check** (for databases, message queues):
```yaml
initContainers:
  - name: wait-for-postgres
    image: busybox:latest
    command: ['sh', '-c', 'until nc -z postgres-service 5432; do echo waiting...; sleep 2; done']
```

**HTTP Health Check** (for web services with readiness endpoints):
```yaml
initContainers:
  - name: wait-for-app-server
    image: curlimages/curl:8.5.0
    command: ['sh', '-c', 'until curl -f http://app-server-service:8000/health; do echo waiting...; sleep 2; done']
```

## Configuration

You can enable/disable dependency waiting in `values.yaml`:

### App Server Example

```yaml
appServer:
  waitForDependencies:
    enabled: true
    services:
      - name: redis
        host: redis-service
        port: 6379
      - name: postgres
        host: postgres-service
        port: 5432
```

### Frontend Example (Mixed TCP + HTTP)

```yaml
frontend:
  waitForDependencies:
    enabled: true
    services:
      - name: redis
        host: redis-service
        port: 6379
    httpChecks:
      - name: app-server
        url: http://app-server-service:8000/health
```

### Disabling for Fast Iteration

During development, you may want to disable waiting. Add to your `laminar.yaml`:

```yaml
appServer:
  waitForDependencies:
    enabled: false  # Pods start immediately
```

Or use command line:

```bash
helm upgrade -i laminar . -f laminar.yaml --set appServer.waitForDependencies.enabled=false
```

## Dependency Tree

Here's the complete dependency graph for this application:

```
┌─────────────────────────────────────────┐
│  Infrastructure (Start First)           │
│  - redis                                │
│  - postgres                             │
│  - clickhouse                           │
│  - rabbitmq                             │
│  - quickwit control plane               │
└──────────────┬──────────────────────────┘
               │
               ├──────────────┐
               │              │
               ▼              ▼
┌──────────────────┐  ┌──────────────────┐
│  Quickwit        │  │  App Servers     │
│  - metastore ────┼─>│  - app-server    │
└────────┬─────────┘  │  - consumer      │
         │            └────────┬─────────┘
         ▼                     │
┌──────────────────┐           │
│  Quickwit Nodes  │           │
│  - indexer       │           │
│  - searcher      │           │
│  - janitor       │           │
└──────────────────┘           │
                               │
                               │
                               ▼
                    ┌───────────────────┐
                    │  Frontend         │
                    │  (depends on all) │
                    └───────────────────┘
```

### Detailed Dependencies

**App Server & Consumer:**
- ✓ Redis (session storage)
- ✓ PostgreSQL (primary database)
- ✓ ClickHouse (analytics)
- ✓ RabbitMQ (message queue)

**Frontend:**
- ✓ Redis (session storage)
- ✓ PostgreSQL (primary database)
- ✓ ClickHouse (analytics)
- ✓ App Server (backend API)
- ✓ App Server Consumer (backend API)

**Quickwit Metastore:**
- ✓ PostgreSQL (metadata storage)

## Best Practices

### 1. Health Checks vs Port Checks

- Use **TCP port checks** (`nc -z`) for databases and message queues
- Use **HTTP health checks** (`curl -f`) for applications with health endpoints
- HTTP checks are more reliable because they verify the service is actually ready

### 2. Timeouts
Init containers will retry indefinitely. If a dependency never becomes ready, the pod stays in `Init:0/N` state. You can inspect with:
```bash
kubectl describe pod <pod-name> -n laminar
kubectl logs <pod-name> -n laminar -c wait-for-<service-name>
```

### 3. Readiness Probes
Init containers ensure dependencies exist, but **readiness probes** prevent traffic before the app is ready:
```yaml
containers:
  - name: app
    readinessProbe:
      httpGet:
        path: /ready
        port: 8000
      initialDelaySeconds: 5
      periodSeconds: 5
```

### 4. Application-Level Retry Logic
Init containers are a safety net, but your application should still:
- Implement retry logic for database connections
- Handle temporary unavailability gracefully
- Use connection pooling with automatic reconnection

## Troubleshooting

### Pod Stuck in Init State

```bash
# Check which init container is waiting
kubectl get pods -n laminar
# NAME            READY   STATUS     RESTARTS   AGE
# app-server-xxx  0/1     Init:2/4   0          5m

# Check init container logs
kubectl logs app-server-xxx -n laminar -c wait-for-postgres
# waiting for postgres...
# waiting for postgres...
```

**Solution:** Check if the dependency service is running:
```bash
kubectl get pods -l app=postgres -n laminar
kubectl describe svc postgres-service -n laminar
```

If it is running, just restart the deployment that creates the problematic pod:
```bash
kubectl -n laminar rollout restart deployment app-server
```

### Disable Init Containers Temporarily

```bash
helm upgrade -i laminar . -f laminar.yaml --set appServer.waitForDependencies.enabled=false
```

### Check Service Connectivity

From within a pod:
```bash
kubectl run -it --rm debug -n laminar --image=busybox --restart=Never -- sh
nc -zv postgres-service 5432
```

## FAQ

**Q: Can I make the frontend wait for the ingress address?**
A: No, the ingress address is assigned after the ingress is created. Use a custom domain instead (see Option 1 above).

**Q: Will init containers slow down my deployments?**
A: Only the first deployment. After that, dependencies are usually already running, so init containers succeed immediately.

**Q: What if I want to start everything at once for development?**
A: Set `waitForDependencies.enabled: false` in your values-dev.yaml override file.
