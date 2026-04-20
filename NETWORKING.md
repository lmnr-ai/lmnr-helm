# Networking Guide

This document explains how Laminar's networking is structured and how to configure DNS, TLS, and ingress for both the frontend and the app server.

## Architecture Overview

Laminar exposes two public endpoints:

| Endpoint | Component | Purpose |
|---|---|---|
| `https://app.yourdomain.com` | Frontend | Web UI |
| `https://api.yourdomain.com:443` | App Server | HTTP trace ingestion (`/v1/*`) |
| `https://api.yourdomain.com:8443` | App Server | gRPC trace ingestion (TLS) |

These are served by two separate mechanisms described below.

---

## Frontend

The frontend is a Next.js app served by a Kubernetes `Deployment`. How it is exposed depends on whether you set a hostname:

**Without a hostname (default):**
- **AWS:** An `Ingress` resource is created with the `alb` ingress class, provisioning an AWS ALB. Get the URL with `kubectl get ingress laminar-frontend-ingress`.
- **GCP:** The `frontend-service` is set to `type: LoadBalancer`, provisioning a GCP Network Load Balancer directly. Get the IP with `kubectl get svc laminar-frontend-service`.

**With a hostname (`frontend.ingress.hostname` set):**
- An `Ingress` resource is created for all providers.
- On GCP the `frontend-service` is automatically set to `type: ClusterIP` — the Ingress handles external exposure.
- TLS can be configured via cert-manager or a pre-existing certificate secret (see [TLS section](#tls) below).
- DNS can be automated via external-dns or set manually.

---

## App Server

The app server exposes **two ports** through a single `LoadBalancer` Service (`laminar-app-server-load-balancer`):

| Port | Target | Protocol | What it is |
|---|---|---|---|
| `443` | `8080` (nginx) | HTTPS/HTTP | HTTP trace ingestion, path-filtered by nginx (`/v1/*` and `/health` only) |
| `8443` | `8001` (Rust) | gRPC (TLS) | gRPC trace ingestion |

This is a Layer 4 (TCP) load balancer on both AWS and GCP — traffic is passed through as-is with no L7 processing by the cloud provider.

**Port 443 — nginx proxy:**
nginx sits in front of the Rust app server as a sidecar container. It only forwards `/v1/*` and `/health` — all other paths return 404. This is intentional to prevent unauthorized access to internal endpoints. nginx listens on port 8080 (plain HTTP); the "443" is just the external port number, there is no TLS termination inside the pod by default.

**Port 8443 — gRPC:**
The Rust app server listens for plaintext gRPC (h2c) on port 8001. When using Traefik, TLS is terminated at the ingress layer and traffic is forwarded as plaintext HTTP/2 to the backend — gRPC clients connect with standard TLS on port 8443.

### TLS for the App Server

**AWS:** TLS is handled by the NLB before traffic reaches the pod. Add the ACM certificate ARN as an annotation (see [CONFIGURATION.md — HTTPS with ACM Certificate](./CONFIGURATION.md#https-with-acm-certificate)).

**GCP:** The GCP Network Load Balancer is pure TCP passthrough — it cannot terminate TLS. Options:

1. **Use a reverse proxy / ingress controller (recommended):** Deploy Traefik in front of the app server to handle TLS termination and cert-manager integration. See [examples/networking/](./examples/networking/) for ready-to-use configurations. This covers both port 443 (HTTP) and port 8443 (gRPC) with full TLS + DNS automation.

2. **TLS inside nginx (advanced):** Mount a cert-manager TLS secret as a volume into the app-server pod and configure nginx for TLS. This is more complex and requires nginx reload on cert rotation.

3. **Private networking / no TLS:** If the app server is only reachable from within the cluster or a private VPC, TLS is not required. SDK clients in the same cluster can use `http://laminar-app-server-service:8000` directly.

**gRPC (port 8443):** When using Traefik, TLS is terminated at the ingress layer — gRPC clients connect with standard TLS on port 8443 and Traefik forwards plaintext h2c to the backend pod on port 8001. No code changes to the Rust server are needed. See [examples/networking/traefik-app-server.yaml](./examples/networking/traefik-app-server.yaml).

---

## DNS

### Automated DNS with external-dns

external-dns watches Kubernetes resources and automatically creates DNS records in your DNS provider.

**Supported DNS providers:** Google Cloud DNS, Route53, Cloudflare, and many others. Note: Namecheap and most registrar DNS products are not supported — use a standalone DNS provider instead.

external-dns works with both `Ingress` resources (via `external-dns.alpha.kubernetes.io/hostname` annotation on the Ingress) and `LoadBalancer` Services (via the same annotation on the Service). For the app server LoadBalancer, enable it in your values:

```yaml
appServer:
  loadBalancer:
    annotations:
      external-dns.alpha.kubernetes.io/hostname: "api.yourdomain.com"
```

### Manual DNS

For the frontend ingress:
```bash
# AWS — get ALB hostname
kubectl get ingress laminar-frontend-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# GCP — get IP
kubectl get ingress laminar-frontend-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# or if no ingress hostname set on GCP:
kubectl get svc laminar-frontend-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

For the app server:
```bash
kubectl get svc laminar-app-server-load-balancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

---

## TLS

### Option A — cert-manager (automatic, recommended for GCP)

cert-manager provisions and renews free Let's Encrypt certificates automatically. It integrates with Ingress resources via the `cert-manager.io/cluster-issuer` annotation.

This works well for the **frontend** and for the **app server HTTP port** when routed through an ingress controller. See [examples/networking/](./examples/networking/) for complete configurations.

### Option B — AWS ACM (recommended for AWS)

AWS Certificate Manager integrates directly with ALB (frontend) and NLB (app server) via annotations. No in-cluster cert management is needed. See [CONFIGURATION.md — HTTPS with ACM Certificate](./CONFIGURATION.md#https-with-acm-certificate).

### Option C — Pre-existing certificate

Import any PEM certificate as a Kubernetes TLS secret:

```bash
cat cert.pem ca-bundle.pem > fullchain.pem

kubectl create secret tls laminar-frontend-tls \
  --cert=fullchain.pem --key=private-key.pem

kubectl create secret tls laminar-app-server-tls \
  --cert=fullchain.pem --key=private-key.pem
```

Then reference it in your values (leave `clusterIssuer` empty):

```yaml
frontend:
  ingress:
    tls:
      enabled: true
      secretName: "laminar-frontend-tls"
      clusterIssuer: ""
```

---

## See Also

- [examples/networking/](./examples/networking/) — ready-to-use Traefik, nginx-ingress, external-dns, and cert-manager configurations
- [CONFIGURATION.md — Ingress and DNS](./CONFIGURATION.md#ingress-and-dns) — values reference
- [CONFIGURATION.md — ClickHouse S3 Storage](./CONFIGURATION.md#clickhouse-s3-storage) — GCS setup
