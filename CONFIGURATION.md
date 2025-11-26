# Configuration Reference

This guide covers all configuration options for the Laminar Helm chart.

## Table of Contents

- [Secrets Management](#secrets-management)
- [Ingress and DNS](#ingress-and-dns)
- [Storage Configuration](#storage-configuration)
- [ClickHouse S3 Storage](#clickhouse-s3-storage)
- [Node Placement](#node-placement)
- [Resource Limits](#resource-limits)

## Secrets Management

The chart supports three secret backends:

1. **Kubernetes Secrets** (default) - Secrets in values file
2. **AWS Secrets Manager** - For EKS with IRSA
3. **HashiCorp Vault** - For on-premises or multi-cloud

### Kubernetes Secrets (Default)

All secrets are provided in `secrets.data`:

```yaml
secrets:
  enabled: true
  data:
    NEXTAUTH_SECRET: "your-secret"
    POSTGRES_PASSWORD: "secure-password"
    CLICKHOUSE_PASSWORD: "secure-password"
    RABBITMQ_DEFAULT_PASS: "secure-password"
    # ... other secrets
```

### AWS Secrets Manager

Fetch secrets from AWS Secrets Manager using the Secrets Store CSI Driver.

**Prerequisites:**

1. Install Secrets Store CSI Driver:
   ```bash
   helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
   helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
     --namespace kube-system \
     --set syncSecret.enabled=true
   ```

2. Install AWS provider:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
   ```

3. Create IRSA:
   ```bash
   eksctl create iamserviceaccount \
     --name lmnr-secrets-sa \
     --namespace default \
     --cluster your-cluster-name \
     --attach-policy-arn arn:aws:iam::ACCOUNT:policy/LaminarSecretsPolicy \
     --approve
   ```

4. Create AWS secret (JSON format):
   ```bash
   aws secretsmanager create-secret \
     --name production/lmnr-secrets \
     --secret-string '{"NEXTAUTH_SECRET":"value","POSTGRES_PASSWORD":"value"}' \
     --region us-east-1
   ```

**Configuration:**

```yaml
secrets:
  awsSecretsManager:
    enabled: true
    region: "us-east-1"
    serviceAccount:
      create: false  # Using eksctl-created SA
      name: "lmnr-secrets-sa"
    clusterName: "production"  # Secret name: production/lmnr-secrets
    secretKeys:
      - NEXTAUTH_SECRET
      - POSTGRES_PASSWORD
      - AUTH_GITHUB_ID
      - AUTH_GITHUB_SECRET

  # Placeholders for AWS-managed secrets
  data:
    NEXTAUTH_SECRET: ""
    POSTGRES_PASSWORD: ""
    AUTH_GITHUB_ID: ""
    AUTH_GITHUB_SECRET: ""
    # Non-sensitive configs (actual values)
    AWS_REGION: "us-east-1"
```

### HashiCorp Vault

**Prerequisites:**

1. Install Secrets Store CSI Driver (same as AWS)
2. Configure Vault Kubernetes auth:
   ```bash
   vault auth enable kubernetes
   vault write auth/kubernetes/role/lmnr-app \
     bound_service_account_names=lmnr-vault-sa \
     bound_service_account_namespaces=default \
     policies=lmnr-app-policy \
     ttl=24h
   ```

**Configuration:**

```yaml
secrets:
  vault:
    enabled: true
    address: "http://vault:8200"
    authPath: "auth/kubernetes"
    role: "lmnr-app"
    serviceAccount:
      create: true
      name: "lmnr-vault-sa"
    kvVersion: "v2"
    secretPath: "secret/data/lmnr"
    secretKeys:
      - NEXTAUTH_SECRET
      - POSTGRES_PASSWORD
```

### Mixed Sources

You can use multiple backends:

```yaml
secrets:
  # Auth tokens from AWS
  awsSecretsManager:
    enabled: true
    secretKeys: [AUTH_GITHUB_ID, AUTH_GITHUB_SECRET]

  # Database passwords from Vault
  vault:
    enabled: true
    secretKeys: [POSTGRES_PASSWORD, CLICKHOUSE_PASSWORD]

  # Other configs from K8s
  data:
    AWS_REGION: "us-east-1"
    S3_TRACE_PAYLOADS_BUCKET: "my-bucket"
```

## Ingress and DNS

### Custom Domain with External-DNS

```yaml
frontend:
  ingress:
    hostname: "app.yourdomain.com"
    externalDns:
      enabled: true
  env:
    nextauthUrl: "https://app.yourdomain.com"
    nextPublicUrl: "https://app.yourdomain.com"
```

### HTTPS with ACM Certificate

```yaml
frontend:
  ingress:
    hostname: "app.yourdomain.com"
    annotations:
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
      alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:region:account:certificate/xxx"
      alb.ingress.kubernetes.io/ssl-redirect: '443'
  env:
    nextauthUrl: "https://app.yourdomain.com"
    nextPublicUrl: "https://app.yourdomain.com"
```

### Manual DNS

Set hostname but manage DNS yourself:

```yaml
frontend:
  ingress:
    hostname: "app.yourdomain.com"
    externalDns:
      enabled: false
```

After deployment, create a CNAME record pointing to the ALB:
```bash
kubectl get ingress frontend-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Storage Configuration

### Default Storage Class

The chart creates a default EBS storage class with configurable availability zones:

```yaml
storage:
  storageClass:
    name: "ebs-sc"
    type: "gp3"  # EBS volume type
    reclaimPolicy: "Retain"  # Keep volumes after deletion
    volumeBindingMode: "WaitForFirstConsumer"
    zones:
      - "us-east-1b"  # Single AZ deployment
```

**Multi-AZ Configuration:**

For high availability across multiple zones:

```yaml
storage:
  storageClass:
    zones:
      - "us-east-1a"
      - "us-east-1b"
      - "us-east-1c"
```

**Important:** Ensure your Kubernetes nodes are running in the zones you specify. Pods with persistent volumes can only be scheduled on nodes in the same zone as their volume.

### Per-Service Storage Classes

Each service can use a different storage class:

```yaml
postgres:
  persistence:
    enabled: true
    storageClass: "gp3"  # Or "io2" for high IOPS
    size: "100Gi"

clickhouse:
  persistence:
    enabled: true
    storageClass: "gp3"
    size: "50Gi"

rabbitmq:
  persistence:
    enabled: true
    storageClass: "gp3"
    size: "10Gi"
```

### EBS Volume Types

- **gp3** - General Purpose SSD (recommended, cost-effective)
- **gp2** - General Purpose SSD (legacy)
- **io1/io2** - Provisioned IOPS SSD (high performance)
- **st1** - Throughput Optimized HDD (big data)
- **sc1** - Cold HDD (infrequent access)

### Creating Custom Storage Classes

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: io2-sc
provisioner: ebs.csi.aws.com
parameters:
  type: io2
  iopsPerGB: "50"
  encrypted: "true"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowedTopologies:
  - matchLabelExpressions:
      - key: topology.kubernetes.io/zone
        values:
          - us-east-1a
          - us-east-1b
```

## ClickHouse S3 Storage

Store ClickHouse data in S3 for cost efficiency and scalability.

```yaml
clickhouse:
  persistence:
    enabled: false  # Disable local storage

  s3:
    enabled: true
    endpoint: "https://my-bucket.s3.us-east-1.amazonaws.com/"
    region: "us-east-1"
    useEnvironmentCredentials: true  # Use IAM role
    cache:
      enabled: true
      maxSize: "50Gi"
```

**Required IAM permissions:**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
  }]
}
```

**Verify S3 storage:**

```bash
kubectl exec clickhouse-0 -- clickhouse-client --query "SELECT * FROM system.disks"
kubectl exec clickhouse-0 -- clickhouse-client --query "SELECT * FROM system.storage_policies"
```

## Node Placement

### Node Selectors

```yaml
postgres:
  nodeSelector:
    disktype: ssd
    node-type: database
```

### Node Affinity

```yaml
appServer:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: alpha.eksctl.io/nodegroup-name
            operator: In
            values:
            - compute-optimized
```

## Resource Limits

Each service can have resource limits configured:

```yaml
appServer:
  resources:
    requests:
      cpu: "0.5"
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "2Gi"

postgres:
  resources:
    requests:
      cpu: "0.5"
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "4Gi"
```

## All Configuration Options

For the complete list of configuration options, see the comments in [values.yaml](./values.yaml).

## Examples

See the [examples/](./examples/) directory for complete configuration examples:

- `clickhouse-s3-storage.yaml` - ClickHouse with S3 backend
- `mixed-storage-classes.yaml` - Different storage classes per service
- `multiple-node-groups.yaml` - Deploy to different node groups
- `secrets/` - Secret management examples (AWS, Vault, mixed)
