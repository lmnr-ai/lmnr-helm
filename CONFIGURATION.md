# Configuration Reference

This guide covers advanced configuration options for the Laminar Helm chart.

> **Note on Namespaces:** All examples in this guide assume the default namespace. If using a custom namespace, add `--namespace <your-namespace>` to `helm` commands and `-n <your-namespace>` to `kubectl` commands.

## Table of Contents

- [Cloud Provider](#cloud-provider)
- [Container Images](#container-images)
- [Secrets Management](#secrets-management)
- [Extra Environment Variables](#extra-environment-variables)
- [OAuth setup](#oauth-setup)
- [LLM Provider](#llm-provider)
- [Ingress and DNS](#ingress-and-dns)
- [Storage Configuration](#storage-configuration)
- [ClickHouse S3 Storage](#clickhouse-s3-storage)
- [Quickwit Storage Backend](#quickwit-storage-backend)
- [Node Placement](#node-placement)
- [Resource Limits](#resource-limits)
- [Upgrading the Chart](#upgrading-the-chart)

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

## Container Images

The three Laminar containers — frontend, app server (used by both `app-server` and `app-server-consumer`), and query engine — are pulled from `ghcr.io/lmnr-ai`:

```yaml
# values.yaml (defaults)
images:
  repository: "ghcr.io/lmnr-ai"
  pullPolicy: Always
  frontend:
    name: "frontend-ee"
    tag: "latest"
  appServer:
    name: "app-server-ee"
    tag: "latest"
  queryEngine:
    name: "query-engine-ee"
    tag: "latest"
```

`ghcr.io/lmnr-ai/*-ee` images are public — `helm install` pulls them on its own and most users never need to think about this section.

### Pinning a specific tag

`tag: "latest"` is convenient but means a `kubectl rollout restart` will pick up whatever was pushed most recently. For production, pin a specific version in your `laminar.yaml`:

```yaml
images:
  frontend:
    tag: "0.1.546"
  appServer:
    tag: "0.1.546"
  queryEngine:
    tag: "0.1.546"
```

Available tags are listed under the [Packages tab on GitHub](https://github.com/orgs/lmnr-ai/packages). The frontend, app server, and query engine are released together — keep their tags in sync.

When pinning to a tag that does not change content, you can also drop `pullPolicy: Always` to avoid an extra registry round-trip on every pod start:

```yaml
images:
  pullPolicy: IfNotPresent
```

### Pulling images manually

If your nodes have no outbound internet access, or you want to mirror images into your own registry, pull them ahead of time:

```bash
docker pull ghcr.io/lmnr-ai/frontend-ee:latest
docker pull ghcr.io/lmnr-ai/app-server-ee:latest
docker pull ghcr.io/lmnr-ai/query-engine-ee:latest
```

Replace `latest` with the tag you intend to deploy. To use a private mirror, retag and push each image, then point the chart at it:

```bash
# Example: mirror to your own registry
docker tag ghcr.io/lmnr-ai/frontend-ee:0.1.546 my-registry.example.com/laminar/frontend-ee:0.1.546
docker push my-registry.example.com/laminar/frontend-ee:0.1.546
# Repeat for app-server-ee and query-engine-ee
```

```yaml
# laminar.yaml
images:
  repository: "my-registry.example.com/laminar"
  pullPolicy: IfNotPresent
  frontend:
    tag: "0.1.546"
  appServer:
    tag: "0.1.546"
  queryEngine:
    tag: "0.1.546"
```

If the mirror requires authentication, the pods need an `imagePullSecrets` entry on the ServiceAccount they run as. The chart does not template this today — create a `docker-registry` secret and patch the default ServiceAccount manually:

```bash
kubectl create secret docker-registry my-registry-creds \
  --docker-server=my-registry.example.com \
  --docker-username=<user> \
  --docker-password=<pass>

kubectl patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"my-registry-creds"}]}'
```

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

## Extra Environment Variables

The `extraEnv` field lets you inject additional environment variables into any of the main deployments (`frontend`, `appServer`, `appServerConsumer`). It accepts a list of standard [Kubernetes env var definitions](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#envvar-v1-core), supporting:

- **Plain values** via `value:`
- **Kubernetes Secret references** via `valueFrom.secretKeyRef`
- **ConfigMap references** via `valueFrom.configMapKeyRef`
- **Pod field references** via `valueFrom.fieldRef`

This is especially useful when you manage secrets externally (e.g., via sealed-secrets, external-secrets-operator, or a Keycloak operator) and need to reference pre-existing Kubernetes Secrets.

`extraEnv` entries take precedence over values injected by `envFrom` (i.e., over `secrets.data`), so they can be used to selectively override individual keys without changing the chart's secrets configuration.

### Example: Reference an existing Kubernetes Secret

```yaml
frontend:
  extraEnv:
    - name: AUTH_KEYCLOAK_ID
      valueFrom:
        secretKeyRef:
          name: keycloak-realm
          key: client-id
    - name: AUTH_KEYCLOAK_SECRET
      valueFrom:
        secretKeyRef:
          name: keycloak-realm
          key: client-secret
    - name: AUTH_KEYCLOAK_ISSUER
      value: "https://keycloak.example.com/realms/my-realm"
```

### Example: Add custom env vars to the app server

```yaml
appServer:
  extraEnv:
    - name: MY_CUSTOM_VAR
      value: "some-value"
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: my-db-credentials
          key: password
```

See also: [`examples/secrets/extra-env.yaml`](./examples/secrets/extra-env.yaml)

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

### Keycloak OIDC Auth

Get your Keycloak **ID** and **Secret** as well as **issuer** (including realm). In `laminar.yaml`

**Option 1: Inline values**

```yaml
secrets:
  data:
    AUTH_KEYCLOAK_ID: "your-keycloak-id"
    AUTH_KEYCLOAK_SECRET: "your-keycloak-secret"
    AUTH_KEYCLOAK_ISSUER: "https://your-keycloak-domain.com/realms/My_Realm"
```

**Option 2: Reference a pre-existing Kubernetes Secret**

If your Keycloak credentials are already stored in a Kubernetes Secret (e.g., created by the Keycloak operator, sealed-secrets, or external-secrets-operator), use `extraEnv` with `secretKeyRef`:

```yaml
frontend:
  extraEnv:
    - name: AUTH_KEYCLOAK_ID
      valueFrom:
        secretKeyRef:
          name: keycloak-realm
          key: client-id
    - name: AUTH_KEYCLOAK_SECRET
      valueFrom:
        secretKeyRef:
          name: keycloak-realm
          key: client-secret
    - name: AUTH_KEYCLOAK_ISSUER
      value: "https://your-keycloak-domain.com/realms/My_Realm"
```

These `extraEnv` entries override any matching keys from `secrets.data`. See [Extra Environment Variables](#extra-environment-variables) for details.

See also: [`examples/secrets/extra-env.yaml`](./examples/secrets/extra-env.yaml)

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
    AUTH_GITHUB_SECRET: "your-github-client-secret"
    AUTH_GOOGLE_ID: "your-google-client-id"
    AUTH_GOOGLE_SECRET: "your-google-client-secret"
    AUTH_AZURE_AD_CLIENT_ID: "your-azure-client-id"
    AUTH_AZURE_AD_CLIENT_SECRET: "your-azure-client-secret"
    AUTH_AZURE_AD_TENANT_ID: "your-azure-tenant-id"
    AUTH_OKTA_CLIENT_ID: "your-okta-client-id"
    AUTH_OKTA_CLIENT_SECRET: "your-okta-client-secret"
    AUTH_OKTA_ISSUER: "https://your-okta-domain.com/oauth2/default"
    AUTH_KEYCLOAK_ID: "your-keycloak-id"
    AUTH_KEYCLOAK_SECRET: "your-keycloak-secret"
    AUTH_KEYCLOAK_ISSUER: "https://your-keycloak-domain.com/realms/My_Realm"

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

## LLM Provider

All AI features (chat-with-trace, SQL-with-AI, signals) share one unified set
of environment variables:

- `LLM_PROVIDER` — one of `gemini` (default), `openai`, `bedrock`. Set via
  `frontend.env.llmProvider`, `appServer.env.llmProvider`, and
  `appServerConsumer.env.llmProvider`. All three default to `gemini`.
- `LLM_API_KEY` — key for `gemini` or `openai`. Set via `secrets.data`.
- `LLM_BASE_URL` — optional, for OpenAI-compatible gateways (LiteLLM,
  OpenRouter, vLLM) or custom Gemini endpoints. Set via `*.env.llmBaseUrl`.
- `LLM_MODEL_SMALL` / `LLM_MODEL_MEDIUM` / `LLM_MODEL_LARGE` — optional
  per-tier model overrides. Per-provider defaults apply when unset. For
  Bedrock, these values are Inference Profile IDs.
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` — used by
  `bedrock` instead of `LLM_API_KEY`. Set via `secrets.data`.

`signalsEnabled` on the frontend defaults to `"true"`; AI features in the
frontend are active as soon as `LLM_API_KEY` (or AWS credentials for
Bedrock) is populated.

### Gemini (default)

Gemini is the default provider — just supply the key:

```yaml
secrets:
  data:
    LLM_API_KEY: "your-gemini-key"
```

### OpenAI (or OpenAI-compatible gateway)

```yaml
frontend:
  env:
    llmProvider: "openai"
    # Optional: OpenAI-compatible gateway (LiteLLM, OpenRouter, vLLM)
    # llmBaseUrl: "http://my-gateway:4000"

appServer:
  env:
    llmProvider: "openai"

appServerConsumer:
  env:
    llmProvider: "openai"

secrets:
  data:
    LLM_API_KEY: "your-openai-or-gateway-key"
```

### AWS Bedrock

Bedrock uses AWS credentials from `secrets.data` instead of `LLM_API_KEY`.

```yaml
frontend:
  env:
    llmProvider: "bedrock"

appServer:
  env:
    llmProvider: "bedrock"

appServerConsumer:
  env:
    llmProvider: "bedrock"

secrets:
  data:
    AWS_ACCESS_KEY_ID: "your-aws-access-key-id"
    AWS_SECRET_ACCESS_KEY: "your-secret-access-key"
    AWS_REGION: "us-east-1" # or another aws region
```

### Model overrides (optional)

Per-provider defaults apply when unset. Override per size tier to pin specific
models (for Bedrock, values are Inference Profile IDs):

```yaml
appServerConsumer:
  env:
    llmModelSmall: "gemini-3-flash-preview"
    llmModelMedium: "gemini-3-flash-preview"
    llmModelLarge: "gemini-3-pro-preview"
```

### Disabling signals

Signals are enabled by default in the frontend. To disable:

```yaml
frontend:
  env:
    signalsEnabled: "false"
```

## Ingress and DNS

> For a full explanation of Laminar's network architecture — how the frontend and app server are exposed, when to use an ingress controller vs a LoadBalancer Service, and how TLS works on each provider — see [NETWORKING.md](./NETWORKING.md) and [examples/networking/](./examples/networking/).

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
kubectl get ingress laminar-frontend-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**For GCP:**
```bash
kubectl get ingress laminar-frontend-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### HTTPS with cert-manager (automatic certificates)

cert-manager automatically provisions and renews free Let's Encrypt certificates. This works on any provider with an ingress controller (Traefik, nginx, etc.).

**1. Install cert-manager:**
```bash
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm upgrade -i cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

**2. Create a ClusterIssuer** (apply with `kubectl apply -f`):
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com   # replace with your email
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik  # match your ingress controller
```

> The hostname must be publicly DNS-resolvable before deploying, so Let's Encrypt can complete the HTTP-01 challenge.

**3. Add to your `laminar.yaml`:**
```yaml
global:
  cloudProvider: "gcp"

frontend:
  ingress:
    hostname: "app.yourdomain.com"
    className: "traefik"
    tls:
      enabled: true
      clusterIssuer: "letsencrypt"
      secretName: "laminar-frontend-tls"
  env:
    nextauthUrl: "https://app.yourdomain.com"
    nextPublicUrl: "https://app.yourdomain.com"
```

> **Note:** When `frontend.ingress.hostname` is set on GCP, the frontend Service automatically uses `ClusterIP` instead of `LoadBalancer` — the Ingress handles external exposure.

### HTTPS with a pre-existing certificate

If you already have a certificate (from a paid CA, ACM export, or wildcard cert), import it as a Kubernetes TLS secret. Concatenate the certificate body and CA bundle into a full chain first:

```bash
cat cert.pem ca-bundle.pem > fullchain.pem

kubectl create secret tls laminar-frontend-tls \
  --cert=fullchain.pem --key=private-key.pem

kubectl create secret tls laminar-app-server-tls \
  --cert=fullchain.pem --key=private-key.pem
```

Then reference it in `laminar.yaml` without a `clusterIssuer`:

```yaml
frontend:
  ingress:
    hostname: "app.yourdomain.com"
    className: "traefik"
    tls:
      enabled: true
      secretName: "laminar-frontend-tls"
      clusterIssuer: ""  # leave empty — cert-manager not needed
```

### App Server Ingress (GCP and other providers)

> **AWS users:** You most likely do **not** need this. The `appServer.loadBalancer` (NLB) already exposes the app server externally on port 443. See [HTTPS with ACM Certificate](#https-with-acm-certificate) for the AWS setup. Use this only if you explicitly prefer an ALB over NLB, or for gRPC-free HTTP-only setups.

For GCP, add an Ingress for the app server alongside the frontend. This is useful when you need to ingest traces from external services (e.g. runtime pods in other clusters).

Add to your `laminar.yaml`:

```yaml
appServer:
  ingress:
    hostname: "api.yourdomain.com"
    className: "traefik"   # your ingress controller class
    externalDns:
      enabled: true        # optional: requires external-dns
    tls:
      enabled: true
      clusterIssuer: "letsencrypt"
      secretName: "laminar-app-server-tls"
```

> **Note:** gRPC traffic (port 8443) is not handled by the Ingress. On AWS, the NLB (`appServer.loadBalancer`) handles gRPC regardless of whether you also use the Ingress.

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

### ClickHouse on GCS (GCP)

GCS supports an S3-compatible API but requires **HMAC credentials** — `useEnvironmentCredentials` does not work because the GKE metadata server returns OAuth2 tokens, which GCS's S3 API does not accept.

**1. Create a service account and generate HMAC keys:**
```bash
gcloud iam service-accounts create clickhouse-gcs --project=YOUR_PROJECT

gsutil iam ch \
  serviceAccount:clickhouse-gcs@YOUR_PROJECT.iam.gserviceaccount.com:objectAdmin \
  gs://YOUR_BUCKET_NAME

gcloud storage hmac create clickhouse-gcs@YOUR_PROJECT.iam.gserviceaccount.com \
  --project=YOUR_PROJECT
# Note the Access ID and Secret printed — you'll need them below
```

**2a. Inline credentials in `laminar.yaml` (simple, but credentials in values):**
```yaml
clickhouse:
  s3:
    enabled: true
    endpoint: "https://storage.googleapis.com/YOUR_BUCKET_NAME/"
    region: ""  # not needed for GCS
    accessKeyId: "GOOG1E..."       # HMAC Access ID from above
    secretAccessKey: "..."         # HMAC Secret from above
    useEnvironmentCredentials: false
    cache:
      enabled: true
      maxSize: "10Gi"
```

**2b. Load credentials from a Kubernetes Secret (recommended):**

Create the secret once:
```bash
kubectl create secret generic clickhouse-gcs-credentials \
  --from-literal=access-key-id=GOOG1E... \
  --from-literal=secret-access-key=...
```

Then reference it in `laminar.yaml`:
```yaml
clickhouse:
  s3:
    enabled: true
    endpoint: "https://storage.googleapis.com/YOUR_BUCKET_NAME/"
    region: ""
    accessKeyIdFrom: "GCS_HMAC_KEY"        # env var name to read the key from
    secretAccessKeyFrom: "GCS_HMAC_SECRET"  # env var name to read the secret from
    useEnvironmentCredentials: false
    cache:
      enabled: true
      maxSize: "10Gi"
  extraEnv:
    - name: GCS_HMAC_KEY
      valueFrom:
        secretKeyRef:
          name: clickhouse-gcs-credentials
          key: access-key-id
    - name: GCS_HMAC_SECRET
      valueFrom:
        secretKeyRef:
          name: clickhouse-gcs-credentials
          key: secret-access-key
```

## Quickwit Storage Backend

Quickwit holds Laminar's full-text search index for spans. By default, the chart points it at AWS S3 in `us-east-1`. The same Quickwit deployment runs against any S3-compatible object store via `quickwit.s3.flavor` and `quickwit.s3.endpoint`.

### Default (AWS S3)

```yaml
quickwit:
  s3:
    defaultIndexRootUri: "s3://my-bucket/indexes"
    region: "us-east-1"
```

On EKS, credentials come from the node's IAM instance role via the AWS metadata service — no extra env vars needed.

### Quickwit on GCS (GKE)

Quickwit does not have a native GCP credential path. Use GCS's S3 interoperability layer with **HMAC keys**, fed in as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.

This section assumes you've already followed [ClickHouse on GCS](#clickhouse-on-gcs-gcp) and have a `clickhouse-gcs` service account with HMAC keys. The chart is designed for one HMAC key pair to back both ClickHouse and Quickwit — you do **not** need a second SA or a second HMAC key.

**1. Grant the existing service account access to the Quickwit bucket:**
```bash
gsutil iam ch \
  serviceAccount:clickhouse-gcs@YOUR_PROJECT.iam.gserviceaccount.com:objectAdmin \
  gs://YOUR_QUICKWIT_BUCKET
```

`objectAdmin` is required — Quickwit deletes objects during split merges and garbage collection, so read-only or create-only roles will fail mid-indexing with `AccessDenied`.

**2. Make sure the HMAC credentials are in a Kubernetes secret.** If you followed step 2b of the ClickHouse section, reuse `clickhouse-gcs-credentials` — the snippet in step 3 below assumes that name. Otherwise, create a Quickwit-specific secret with the same HMAC key pair:
```bash
kubectl create secret generic quickwit-gcs-credentials \
  --from-literal=access-key-id=GOOG1... \
  --from-literal=secret-access-key=...
```
…and use `quickwit-gcs-credentials` as the `secretKeyRef.name` in step 3.

**3. Configure `laminar.yaml`:**
```yaml
quickwit:
  s3:
    defaultIndexRootUri: "s3://my-quickwit-bucket/indexes"
    region: "us-central1"
  extraEnv:
    - name: AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: quickwit-gcs-credentials 
          key: access-key-id # HMAC Access ID
    - name: AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: quickwit-gcs-credentials
          key: secret-access-key # HMAC Secret
```

When `global.cloudProvider: gcp`, the chart auto-fills `quickwit.s3.flavor: "gcs"` and `quickwit.s3.endpoint: "https://storage.googleapis.com"` for you — that's the important bit, since Quickwit's `gcs` flavor disables multi-object delete and multipart upload (which GCS's S3 interop layer doesn't fully support). Set either knob explicitly only when you want to override the default, e.g. pointing at MinIO or a custom S3-compatible endpoint.

`quickwit.extraEnv` is propagated to all five Quickwit components (control-plane, indexer, janitor, metastore, searcher). For overrides that should only apply to one component, use the per-component knob — e.g. `quickwit.indexer.extraEnv` — which is appended after `quickwit.extraEnv`.

A complete example also lives in [`examples/quickwit-gcs-storage.yaml`](./examples/quickwit-gcs-storage.yaml).

See [Quickwit's storage configuration reference](https://quickwit.io/docs/configuration/storage-config) for the full list of supported flavors.

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

## Upgrading the Chart

The standard upgrade is:

```bash
helm upgrade -i laminar ./charts/laminar -f laminar.yaml
```

For routine upgrades within a minor (`0.1.x` → `0.1.y`), this is enough — Deployments roll over and StatefulSets restart their pods one at a time.

### Upgrading from <= 0.1.11 to >= 0.1.12

`0.1.12` rebuilt the RabbitMQ and Quickwit indexer/searcher templates. Two things changed that an in-place `helm upgrade` cannot apply:

- **Quickwit indexer and searcher** gained a conditional `volumeClaimTemplates` block (active when `persistence.enabled: true`). `spec.volumeClaimTemplates` is immutable on a StatefulSet, so even if you leave persistence off, the diff trips Kubernetes' validation when other fields move around it.
- **RabbitMQ and the Quickwit indexer** picked up a `checksum/config` annotation on their pod templates, so a ConfigMap change (`rabbitmq.conf`, Quickwit `node.yaml`) now actually rolls the pods. On its own this is a normal pod-template diff and not a problem, but it lands in the same upgrade as the Quickwit volumeClaimTemplates change.

The upgrade fails with errors like:

```
Forbidden: updates to statefulset spec for fields other than 'replicas',
'ordinals', 'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy'
and 'minReadySeconds' are forbidden
```

Delete the affected StatefulSets with `--cascade=orphan` (which keeps the running pods serving traffic) and let `helm upgrade` recreate them with the new spec:

```bash
kubectl delete statefulset laminar-rabbitmq --cascade=orphan
kubectl delete statefulset laminar-quickwit-indexer --cascade=orphan
kubectl delete statefulset laminar-quickwit-searcher --cascade=orphan

helm upgrade -i laminar ./charts/laminar -f laminar.yaml
```

The new StatefulSets adopt the existing pods (matched by labels), then each pod is restarted on its own with the updated template. PVCs are preserved — RabbitMQ keeps its WAL, and the Quickwit nodes keep their local working data. Any data that lives in S3 (Quickwit splits, ClickHouse on S3) is untouched regardless.

> ClickHouse and Postgres StatefulSets did not change in `0.1.12`. Don't delete them unless a future release note says to — losing the StatefulSet on a database with a PVC bound is recoverable, but it's a risk you don't need to take on a routine upgrade.

### Switching the Quickwit indexer/searcher to PVC-backed storage

Setting `quickwit.indexer.persistence.enabled: true` (or the same on `searcher`) on an existing install requires recreating the StatefulSet, because `volumeClaimTemplates` is immutable:

```bash
kubectl delete statefulset laminar-quickwit-indexer --cascade=orphan
helm upgrade -i laminar ./charts/laminar -f laminar.yaml
```

The new pod re-fetches working state from S3 on startup; final splits live in S3 regardless.

### When in doubt

`kubectl describe statefulset <name>` shows the current spec, and `helm get manifest laminar` shows what the chart wants it to be. Diff the two before deciding to delete anything.