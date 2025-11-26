# Laminar Helm Chart

Deploy Laminar on Kubernetes with a single command.

## What's Included

- **Frontend** - Web application with ALB ingress
- **App Server** - Backend API with NLB for gRPC/HTTP
- **PostgreSQL** - Primary database (StatefulSet with persistence)
- **ClickHouse** - Analytics database (StatefulSet with persistence)
- **Redis** - Cache and session store
- **RabbitMQ** - Message queue (StatefulSet with persistence)
- **Quickwit** - Full-text search engine

## Quick Start

```bash
# Install
helm install laminar . -f values.yaml

# Get ALB URL (wait 1-2 minutes for provisioning)
ALB_URL=$(kubectl get ingress frontend-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Configure frontend URLs
helm upgrade laminar . -f values.yaml \
  --set frontend.env.nextauthUrl="http://$ALB_URL" \
  --set frontend.env.nextPublicUrl="http://$ALB_URL"
```

See [QUICKSTART.md](./QUICKSTART.md) for detailed installation steps.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         External Traffic                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    ┌──────────────┐                    ┌──────────────┐         │
│    │   AWS ALB    │                    │   AWS NLB    │         │
│    │  (HTTP/S)    │                    │ (gRPC/HTTP)  │         │
│    └──────┬───────┘                    └──────┬───────┘         │
│           │                                   │                 │
│           ▼                                   ▼                 │
│    ┌──────────────┐                    ┌──────────────┐         │
│    │   Frontend   │───────────────────▶│  App Server  │         │
│    │   (Next.js)  │                    │   (Rust)     │         │
│    └──────┬───────┘                    └──────┬───────┘         │
│           │                                   │                 │
├───────────┼───────────────────────────────────┼─────────────────┤
│           │           Internal Services       │                 │
│           │                                   │                 │
│    ┌──────┴───────────────────────────────────┴──────┐          │
│    │                                                 │          │
│    ▼                  ▼                ▼             ▼          │
│ ┌──────┐        ┌──────────┐      ┌──────────┐  ┌──────────┐    │
│ │Redis │        │PostgreSQL│      │ClickHouse│  │ RabbitMQ │    │
│ └──────┘        └──────────┘      └──────────┘  └──────────┘    │
│                                                                 │
│                        ┌──────────┐                             │
│                        │ Quickwit │                             │
│                        └──────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Kubernetes cluster (EKS recommended)
- Helm 3.x
- [AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
- [EBS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)

## Configuration

### Minimal Configuration

The only required configuration is the frontend URL:

```yaml
frontend:
  env:
    nextauthUrl: "https://app.yourdomain.com"
    nextPublicUrl: "https://app.yourdomain.com"
```

### Production Configuration

For production deployments, you should:

1. **Set secure passwords** for PostgreSQL, ClickHouse, and RabbitMQ
2. **Configure secrets** using AWS Secrets Manager or HashiCorp Vault
3. **Enable HTTPS** with an ACM certificate
4. **Configure S3** for ClickHouse and trace storage

See [CONFIGURATION.md](./CONFIGURATION.md) for complete configuration reference.

## Common Operations

### Check Status

```bash
kubectl get pods
kubectl get svc
kubectl get ingress
```

### View Logs

```bash
kubectl logs -l app=frontend -f
kubectl logs -l app=app-server -f
```

### Access Databases

```bash
# PostgreSQL
kubectl exec -it postgres-0 -- psql -U lmnr -d lmnr

# ClickHouse
kubectl exec -it clickhouse-0 -- clickhouse-client
```

### Upgrade

```bash
helm upgrade laminar . -f values.yaml
```

### Uninstall

```bash
helm uninstall laminar

# To also delete persistent data:
kubectl delete pvc -l app=postgres
kubectl delete pvc -l app=clickhouse
kubectl delete pvc -l app=rabbitmq
```

## Documentation

- [QUICKSTART.md](./QUICKSTART.md) - Quickstart tutorial
- [CONFIGURATION.md](./CONFIGURATION.md) - All configuration options
- [DEPENDENCIES.md](./DEPENDENCIES.md) - How service startup order works
- [examples/](./examples/) - Example configurations
