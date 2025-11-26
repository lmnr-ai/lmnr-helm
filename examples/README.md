# Configuration Examples

Example configurations for common deployment scenarios.

## Available Examples

### ClickHouse with S3 Storage (`clickhouse-s3-storage.yaml`)

Store ClickHouse data in S3 instead of local EBS volumes.

**Use case:** Lower storage costs, scale storage independently from compute.

**Note:** The default `laminar.yaml` already includes ClickHouse S3 configuration. Use this example for additional customization.

```bash
helm upgrade -i laminar .. -f ../laminar.yaml -f clickhouse-s3-storage.yaml --namespace laminar --create-namespace
```

### Mixed Storage Classes (`mixed-storage-classes.yaml`)

Use different storage classes for different services based on performance needs.

**Use case:** High IOPS for PostgreSQL, standard storage for RabbitMQ.

```bash
helm upgrade -i laminar .. -f ../laminar.yaml -f mixed-storage-classes.yaml --namespace laminar --create-namespace
```

### Multiple Node Groups (`multiple-node-groups.yaml`)

Deploy services to different node groups based on resource requirements.

**Use case:** Compute-optimized nodes for app servers, storage-optimized for databases.

```bash
helm upgrade -i laminar .. -f ../laminar.yaml -f multiple-node-groups.yaml --namespace laminar --create-namespace
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
  --namespace laminar \
  --create-namespace \
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
# Check pod placement
kubectl get pods -n laminar -o wide

# Check storage
kubectl get pvc -n laminar

# Check ClickHouse S3 config
kubectl exec clickhouse-0 -n laminar -- clickhouse-client --query "SELECT * FROM system.disks"
```
