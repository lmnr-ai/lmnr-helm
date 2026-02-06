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
# 1. Customize laminar.yaml with your AWS credentials and S3 buckets

# 2. Install
helm upgrade -i laminar . -f laminar.yaml

# 3. Get ALB URL (wait 1-2 minutes for provisioning)
ALB_URL=$(kubectl get ingress laminar-frontend-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# 4. Configure frontend URLs
helm upgrade -i laminar . -f laminar.yaml \
  --set frontend.env.nextauthUrl="http://$ALB_URL" \
  --set frontend.env.nextPublicUrl="http://$ALB_URL"

# 5. Get the LMNR_BASE_URL (to send traces to)
LMNR_BASE_URL=$(kubectl get svc laminar-app-server-load-balancer -o jsonpath='{.status.loadBalancer.ingress[0].hostname}') && echo $LMNR_BASE_URL
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
- Helm >=3.x
- [AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
- [EBS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)

> **Note on Namespaces:** By default, all resources are created in the `default` namespace. Advanced users who prefer a custom namespace (e.g., `laminar`) should add `--namespace laminar --create-namespace` to `helm` commands and `-n laminar` to `kubectl` commands.

## Configuration

### Configuration Files

- **`laminar.yaml`** - Your custom configuration (edit this)
- **`values.yaml`** - Base defaults (don't edit, use for reference)

Helm merges both files, with `laminar.yaml` taking precedence.

### Minimal Configuration

Edit `laminar.yaml` and set:

1. **AWS credentials and S3 buckets** for trace storage
2. **ClickHouse S3 bucket** endpoint and region
3. **Availability zones** for EBS volumes
4. **Frontend URLs** (can be set after initial deployment)

```yaml
secrets:
  data:
    AWS_ACCESS_KEY_ID: "your-key"
    AWS_SECRET_ACCESS_KEY: "your-secret"
    S3_TRACE_PAYLOADS_BUCKET: "your-bucket"
    NEXTAUTH_SECRET: "random-secret-string"

clickhouse:
  s3:
    endpoint: "https://your-bucket.s3.us-east-1.amazonaws.com/"
    region: "us-east-1"

storage:
  zones:
    - "us-east-1b"
```

### Production Configuration

For production deployments, additionally configure:

1. **OAuth Configuration** for logging in to the UI platform. Google and Github are supported.
2. **Secure passwords** for PostgreSQL, ClickHouse, and RabbitMQ (in secrets.data)
3. **External secret management** (AWS Secrets Manager or HashiCorp Vault)
4. **HTTPS** with an ACM certificate
5. **Custom domain** with external-dns

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
kubectl logs -l app=laminar-frontend -f
kubectl logs -l app=laminar-app-server -f
```

### Access Databases

```bash
# PostgreSQL
kubectl exec -it laminar-postgres-0 -- psql -U lmnr -d lmnr

# ClickHouse
kubectl exec -it laminar-clickhouse-0 -- clickhouse-client
```

### Upgrade

```bash
helm upgrade -i laminar . -f laminar.yaml
```

### Uninstall

```bash
helm uninstall laminar

# To also delete persistent data:
kubectl delete pvc -l app=laminar-postgres
kubectl delete pvc -l app=laminar-clickhouse
kubectl delete pvc -l app=laminar-rabbitmq
```

## Documentation

- [QUICKSTART.md](./QUICKSTART.md) - Quickstart tutorial
- [CONFIGURATION.md](./CONFIGURATION.md) - All configuration options
- [DEPENDENCIES.md](./DEPENDENCIES.md) - How service startup order works
- [examples/](./examples/) - Example configurations
