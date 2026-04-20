# Networking Examples

Ready-to-use configurations for ingress controllers, DNS automation, and TLS certificate management.

See [NETWORKING.md](../../NETWORKING.md) for a full explanation of Laminar's network architecture before applying these.

## Files

| File | Purpose |
|---|---|
| `traefik-install.yaml` | Traefik Helm values for installation |
| `traefik-frontend.yaml` | Traefik `IngressRoute` for the frontend (HTTP + HTTPS) |
| `traefik-app-server.yaml` | Traefik routes for app server: HTTPS on port 443, TLS-terminating gRPC on port 8443 |
| `cert-manager-clusterissuer.yaml` | Let's Encrypt `ClusterIssuer` for automatic TLS |
| `external-dns-gcp.yaml` | external-dns Helm values for Google Cloud DNS |
| `external-dns-route53.yaml` | external-dns Helm values for AWS Route53 |

## Quick Setup (GCP + Traefik + cert-manager)

```bash
# 1. Install Traefik
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm upgrade -i traefik traefik/traefik \
  --namespace traefik --create-namespace \
  -f traefik-install.yaml

# 2. Get Traefik's external IP — point your DNS A records here
kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# 3. Install cert-manager
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm upgrade -i cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true

# 4. Create ClusterIssuer (edit your email first)
kubectl apply -f cert-manager-clusterissuer.yaml

# 5. Apply Traefik routes (edit hostnames first)
kubectl apply -f traefik-frontend.yaml
kubectl apply -f traefik-app-server.yaml

# 6. Install/upgrade Laminar with your values
helm upgrade -i laminar ../../charts/laminar -f ../../laminar.yaml
```

## Port Reference

| External port | Routes to | Protocol |
|---|---|---|
| `443` (frontend) | `laminar-frontend-service:80` | HTTPS → HTTP |
| `443` (app server) | `laminar-app-server-service:8080` (nginx sidecar) | HTTPS → HTTP; nginx filters to `/v1/*` and `/health` |
| `8443` (app server) | `laminar-app-server-service:8001` (gRPC) | HTTPS → h2c; Traefik terminates TLS, forwards plaintext HTTP/2 |

> **Important:** Ports `8080` and `8001` are only added to `laminar-app-server-service` when `appServer.ingress.hostname` is set in your values. If you are using Traefik's `IngressRoute` CRD instead of a standard Kubernetes `Ingress`, you must still set `appServer.ingress.hostname` in your Laminar values so these ports are exposed on the ClusterIP Service. Without it, both the HTTPS and gRPC Traefik routes will fail to connect.
