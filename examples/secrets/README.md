# Secret Management Examples

Examples for configuring different secret backends.

## Examples

| File | Description |
|------|-------------|
| `kubernetes-only.yaml` | All secrets in values file (default) |
| `aws-all-secrets.yaml` | All secrets from AWS Secrets Manager |
| `aws-partial-secrets.yaml` | Sensitive secrets from AWS, rest from K8s |
| `vault-all-secrets.yaml` | All secrets from HashiCorp Vault |
| `mixed-aws-vault.yaml` | Mix of AWS, Vault, and K8s secrets |

## Usage

```bash
helm install laminar ../.. -f aws-all-secrets.yaml
```

## Prerequisites

For AWS or Vault, you need the Secrets Store CSI Driver:

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true
```

For AWS, also install the AWS provider:

```bash
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
```

## See Also

[CONFIGURATION.md](../../CONFIGURATION.md#secrets-management) for detailed setup instructions.
