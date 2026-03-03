# Configuration Reference

This guide covers advanced configuration options for the Laminar Helm chart.

> **Note on Namespaces:** All examples in this guide assume the default namespace. If using a custom namespace, add `--namespace <your-namespace>` to `helm` commands and `-n <your-namespace>` to `kubectl` commands.

## Table of Contents

- [Cloud Provider](#cloud-provider)
- [Secrets Management](#secrets-management)
- [OAuth setup](#oauth-setup)
- [Ingress and DNS](#ingress-and-dns)
- [Storage Configuration](#storage-configuration)
- [ClickHouse S3 Storage](#clickhouse-s3-storage)
- [Node Placement](#node-placement)
- [Resource Limits](#resource-limits)

## Cloud Provider

This chart supports multiple cloud providers. This setting determines the default Ingress class, storage provisioners, and platform-specific annotations.

Set the provider in your `laminar.yaml`:

```yaml
global:
  # Supported values: "aws" (default), "gcp"
  cloudProvider: "gcp"
```

### Supported Providers

- **AWS**: Uses AWS Load Balancer Controller (`alb` Ingress class) and EBS CSI Driver.
- **GCP**: Uses GCE Ingress (`gce` Ingress class) and GCE Persistent Disk CSI Driver.

## Secrets Management

The chart supports three secret backends:

1. **Kubernetes Secrets** (default) - Secrets in values file
2. **AWS Secrets Manager** - For EKS with IRSA
3. **HashiCorp Vault** - For on-premises or multi-cloud

### Kubernetes Secrets (Default)

All secrets are provided in `secrets.data` in your `laminar.yaml` file:

```yaml
secrets:
  enabled: true
  data:
    NEXTAUTH_SECRET: "your-secret"
    AWS_ACCESS_KEY_ID: "your-aws-access-key-id"
    AWS_SECRET_ACCESS_KEY: "your-secret-access-key"
    AWS_REGION: "us-east-1"
    # ... other secrets

frontend:
  env:
    nextauthUrl: "https://localhost:3000"
    nextPublicUrl: "https://localhost:3000"
```

Install with:

```bash
helm upgrade -i laminar . -f laminar.yaml
```

After updating secrets, restart dependent deployments

```bash
kubectl rollout restart deployment laminar-frontend
```

### AWS Secrets Manager

Fetch secrets from AWS Secrets Manager using the Secrets Store CSI Driver.

**Prerequisites:**

1. Install Secrets Store CSI Driver:
   ```bash
    helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
    helm upgrade --install -n kube-system --set syncSecret.enabled=true --set enableSecretRotation=true csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver
    # it is important to include syncSecret.enabled=true so that csi-secrets-store will be able to get secrets from aws secret manager
    # enableSecretRotation=true will make sure that new secrets will be pull from AWS secret manager if updated
    helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
    helm install -n kube-system secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws
   ```

2. Create policy to read secrets. Name it LaminarSecretsPolicy:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "secretsmanager:GetSecretValue",
            "Resource": "*" # to read all secrets
        }
    ]
}
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

**Configuration in `laminar.yaml`:**

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

Install with:

```bash
helm upgrade -i laminar . -f laminar.yaml
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

**Configuration in `laminar.yaml`:**

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

Install with:

```bash
helm upgrade -i laminar . -f laminar.yaml
```

### Mixed Sources

You can use multiple backends in your `laminar.yaml`:

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
```

Install with:

```bash
helm upgrade -i laminar . -f laminar.yaml
```

## OAuth setup

Laminar supports OAuth authentication with GitHub, Google, and Azure AD. Configure by adding provider credentials to your `laminar.yaml`.

### GitHub OAuth

Create an OAuth App at https://github.com/settings/developers with callback URL: `https://app.yourdomain.com/api/auth/callback/github`

Copy the **Client ID** and **Client Secret** to your `laminar.yaml`:

```yaml
secrets:
  data:
    AUTH_GITHUB_ID: "your-github-client-id"
    AUTH_GITHUB_SECRET: "your-github-client-secret"
```

### Google OAuth

Create an OAuth Client at https://console.cloud.google.com/apis/credentials with redirect URI: `https://app.yourdomain.com/api/auth/callback/google`

Copy the **Client ID** and **Client Secret** to your `laminar.yaml`:

```yaml
secrets:
  data:
    AUTH_GOOGLE_ID: "your-google-client-id"
    AUTH_GOOGLE_SECRET: "your-google-client-secret"
```

### Azure AD OAuth

Create an App Registration at https://portal.azure.com with redirect URI: `https://app.yourdomain.com/api/auth/callback/azure-ad`

Copy the **Application (client) ID**, **Client Secret**, and **Directory (tenant) ID** to your `laminar.yaml`:

```yaml
secrets:
  data:
    AUTH_AZURE_AD_CLIENT_ID: "your-azure-client-id"
    AUTH_AZURE_AD_CLIENT_SECRET: "your-azure-client-secret"
    AUTH_AZURE_AD_TENANT_ID: "your-azure-tenant-id"
```

### Okta OIDC Auth

Get your Okta **Client ID** and **Client Secret** as well as **OIDC issuer**. In `laminar.yaml`

```yaml
secrets:
  data:
    AUTH_OKTA_CLIENT_ID: "your-okta-client-id"
    AUTH_OKTA_CLIENT_SECRET: "your-okta-client-secret"
    AUTH_OKTA_ISSUER: "https://your-okta-domain.com/oauth2/default"
```

### Complete Example

Configure one or more OAuth providers in your `laminar.yaml`:

```yaml
secrets:
  enabled: true
  data:
    NEXTAUTH_SECRET: "your-nextauth-secret"
    AWS_ACCESS_KEY_ID: "your-aws-access-key"
    AWS_SECRET_ACCESS_KEY: "your-aws-secret-key"
    AWS_REGION: "us-east-1"
    
    # OAuth Providers (optional, configure as needed)
    AUTH_GITHUB_ID: "your-github-client-id"
    AUTH_GITHUB_SECRET: j"your-github-client-secret"
    AUTH_GOOGLE_ID: "your-google-client-id"
    AUTH_GOOGLE_SECRET: "your-google-client-secret"
    AUTH_AZURE_AD_CLIENT_ID: "your-azure-client-id"
    AUTH_AZURE_AD_CLIENT_SECRET: "your-azure-client-secret"
    AUTH_AZURE_AD_TENANT_ID: "your-azure-tenant-id"
    AUTH_OKTA_CLIENT_ID: "your-okta-client-id"
    AUTH_OKTA_CLIENT_SECRET: "your-okta-client-secret"
    AUTH_OKTA_ISSUER: "https://your-okta-domain.com/oauth2/default"

frontend:
  env:
    nextauthUrl: "https://app.yourdomain.com"
    nextPublicUrl: "https://app.yourdomain.com"
```

Install or upgrade:

```bash
helm upgrade -i laminar . -f laminar.yaml
```

**Note:** Ensure callback/redirect URLs match your `nextauthUrl` exactly. Omit provider credentials to disable that provider

## Ingress and DNS

### Custom Domain with External-DNS

Add to your `laminar.yaml`:

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

Install with:

```bash
helm upgrade -i laminar . -f laminar.yaml
```

### HTTPS with ACM Certificate


**AWS example**

Add to your `laminar.yaml`:

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

Install with:

```bash
helm upgrade -i laminar . -f laminar.yaml
```

### Manual DNS

Set hostname but manage DNS yourself in your `laminar.yaml`:

```yaml
frontend:
  ingress:
    hostname: "app.yourdomain.com"
    externalDns:
      enabled: false
```

After deployment, create a CNAME record pointing to the ALB:

**For AWS:**
```bash
kubectl get ingress laminar-frontend-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**For GCP:**
```bash
kubectl get svc laminar-frontend-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Storage Configuration

### Default Storage Class

The chart creates a default EBS storage class with configurable availability zones. In your `laminar.yaml`:

```yaml
storage:
  zones:
    - "us-east-1b"  # Single AZ deployment
```

The full storage class configuration is in `values.yaml` and can be overridden:

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

For high availability across multiple zones in your `laminar.yaml`:

```yaml
storage:
  zones:
    - "us-east-1a"
    - "us-east-1b"
    - "us-east-1c"
```

**Important:** Ensure your Kubernetes nodes are running in the zones you specify. Pods with persistent volumes can only be scheduled on nodes in the same zone as their volume.

### Per-Service Storage Classes

Each service can use a different storage class. Add to your `laminar.yaml`:

```yaml
postgres:
  persistence:
    storageClass: "io2"  # High IOPS for database
    size: "100Gi"

clickhouse:
  persistence:
    storageClass: "gp3"
    size: "50Gi"

rabbitmq:
  persistence:
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
      - key: topology.ebs.csi.aws.com/zone
        values:
          - us-east-1a
          - us-east-1b
```

## ClickHouse S3 Storage

Store ClickHouse data in S3 for cost efficiency and scalability. The `laminar.yaml` template includes this by default:

```yaml
clickhouse:
  persistence:
    enabled: false  # Disable local storage (optional)

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
kubectl exec laminar-clickhouse-0 -- clickhouse-client --query "SELECT * FROM system.disks"
kubectl exec laminar-clickhouse-0 -- clickhouse-client --query "SELECT * FROM system.storage_policies"
```

## Node Placement

### Node Selectors

Add to your `laminar.yaml` to control pod placement:

```yaml
postgres:
  nodeSelector:
    disktype: ssd
    node-type: database
```

### Node Affinity

Add to your `laminar.yaml`:

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

Each service can have resource limits configured. Add to your `laminar.yaml`:

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

- **Base defaults:** See [values.yaml](./values.yaml) for all available options
- **Your overrides:** Edit [laminar.yaml](./laminar.yaml) with your specific settings
- Helm merges both files, with `laminar.yaml` taking precedence

## Examples

See the [examples/](./examples/) directory for complete configuration examples:

- `clickhouse-s3-storage.yaml` - ClickHouse with S3 backend
- `mixed-storage-classes.yaml` - Different storage classes per service
- `multiple-node-groups.yaml` - Deploy to different node groups
- `secrets/` - Secret management examples (AWS, Vault, mixed)

Use examples as additional override files:

```bash
helm upgrade -i laminar . -f laminar.yaml -f examples/mixed-storage-classes.yaml
```


## ClickHouse Logging

By default, ClickHouse logging is **disabled** (`level: none`) to reduce storage overhead and disk I/O. ClickHouse's default logging level is `trace`, which is [extremely verbose](https://clickhouse.com/docs/knowledgebase/why_default_logging_verbose) and can consume significant disk space and affect performance.

### Enabling Logging

To enable logging for debugging or monitoring:

1. Edit `templates/clickhouse-configmap.yaml`
2. Change the logger level from `none` to a desired level:
   ```xml
   <logger>
     <level>warning</level>  <!-- Change from 'none' to 'warning', 'error', or 'information' -->
   </logger>
   ```
3. Apply the changes:
   ```bash
   helm upgrade laminar-dataplane . --namespace laminar --reuse-values
   kubectl rollout restart statefulset laminar-clickhouse -n laminar
   ```

### Available Log Levels

From least to most verbose:

- `none` - Logging disabled (default)
- `fatal` - Only fatal errors
- `critical` - Critical errors
- `error` - All errors
- `warning` - Warnings and errors (recommended for production)
- `notice` - Important notices
- `information` - General informational messages
- `debug` - Debug information
- `trace` - Very detailed tracing (not recommended - extremely verbose)

**Recommendation:** Use `warning` or `error` for production environments. Avoid `trace` and `debug` levels unless actively troubleshooting specific issues.

### System Tables

ClickHouse also logs various operational data to system tables (query logs, metrics, etc.). These are controlled separately from the logger level. If you need these, you can add configurations like:

```xml
<clickhouse>
  <query_log>
    <database>system</database>
    <table>query_log</table>
    <partition_by>toYYYYMM(event_date)</partition_by>
    <ttl>event_date + INTERVAL 48 HOUR</ttl>
    <flush_interval_milliseconds>7500</flush_interval_milliseconds>
  </query_log>
</clickhouse>
```

We recommend setting short rotation periods on all of the tables,
if you enable logging at all.

For more information, see the [ClickHouse logging documentation](https://clickhouse.com/docs/knowledgebase/why_default_logging_verbose).
