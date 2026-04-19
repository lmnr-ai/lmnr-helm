# Configuration Examples

Example configurations for common deployment scenarios.

> **Note on Namespaces:** All examples assume the default namespace. If using a custom namespace, add `--namespace <your-namespace> --create-namespace` to the `helm` commands below.

## Available Examples

### Networking (`networking/`)

Ingress controllers, TLS, DNS, and cert-manager configurations for exposing Laminar externally.

- `traefik-install.yaml` — Traefik Helm values (includes port 8443 entrypoint for gRPC)
- `traefik-frontend.yaml` — HTTPS IngressRoute for the frontend with cert-manager
- `traefik-app-server.yaml` — HTTPS IngressRoute (port 443) + TCP passthrough (port 8443) for the app server
- `cert-manager-clusterissuer.yaml` — Let's Encrypt ClusterIssuer
- `external-dns-gcp.yaml` — external-dns for Google Cloud DNS
- `external-dns-route53.yaml` — external-dns for AWS Route53

See [networking/README.md](./networking/README.md) for setup instructions and [NETWORKING.md](../NETWORKING.md) for architecture explanation.

### ClickHouse with S3 Storage (`clickhouse-s3-storage.yaml`)

Store ClickHouse data in S3 instead of local EBS volumes.

**Use case:** Lower storage costs, scale storage independently from compute.

**Note:** The default `laminar.yaml` already includes ClickHouse S3 configuration. Use this example for additional customization.

```bash
helm upgrade -i laminar .. -f ../laminar.yaml -f clickhouse-s3-storage.yaml
```

### Mixed Storage Classes (`mixed-storage-classes.yaml`)

Use different storage classes for different services based on performance needs.

**Use case:** High IOPS for PostgreSQL, standard storage for RabbitMQ.

```bash
helm upgrade -i laminar .. -f ../laminar.yaml -f mixed-storage-classes.yaml
```

### Multiple Node Groups (`multiple-node-groups.yaml`)

Deploy services to different node groups based on resource requirements.

**Use case:** Compute-optimized nodes for app servers, storage-optimized for databases.

```bash
helm upgrade -i laminar .. -f ../laminar.yaml -f multiple-node-groups.yaml
```

### Secrets Management (`secrets/`)

Examples for different secret management backends:

- `kubernetes-only.yaml` - Traditional K8s secrets
- `aws-all-secrets.yaml` - All secrets from AWS Secrets Manager
- `aws-partial-secrets.yaml` - Sensitive secrets from AWS, rest from K8s
- `vault-all-secrets.yaml` - All secrets from HashiCorp Vault
- `mixed-aws-vault.yaml` - Mix of AWS, Vault, and K8s secrets

## Combining Examples

You can combine multiple example files. Files are merged left-to-right, with later files taking precedence:

```bash
helm upgrade -i laminar .. \
  -f ../laminar.yaml \
  -f mixed-storage-classes.yaml \
  -f multiple-node-groups.yaml
```

## Customizing

Before deploying, update placeholder values:

- S3 bucket names and regions
- Node group names
- Storage class names
- IAM role ARNs

## Verification

```bash
kubectl get pods -o wide

kubectl get pvc

kubectl exec laminar-clickhouse-0 -- clickhouse-client --query "SELECT * FROM system.disks"
```
