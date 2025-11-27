# Quick Start Guide

Get Laminar running on your Kubernetes cluster in minutes.

## Prerequisites

- Kubernetes cluster (EKS recommended)
- Helm 3.x
- [AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) installed
- [EBS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) installed

> **Note on Namespaces:** By default, all resources are created in the `default` namespace. If you prefer using a custom namespace (e.g., `laminar`), add `--namespace laminar --create-namespace` to all `helm` commands and `-n laminar` to all `kubectl` commands in this guide.

## Installation

### Step 1: Customize Configuration

Copy and edit `laminar.yaml` with your settings:

- Set AWS credentials and S3 bucket names
- Set ClickHouse S3 bucket endpoint and region
- Set your availability zone(s)

### Step 2: Install with Customized Settings

Install Laminar with your customized configuration:

```bash
helm upgrade -i laminar . -f laminar.yaml
```

### Step 3: Get the Load Balancer URL

Wait for the ALB to be provisioned (1-2 minutes), then get the URL:

```bash
kubectl get ingress laminar-frontend-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Step 4: Configure Frontend URLs

Update `laminar.yaml` with the ALB URL or upgrade directly:

```bash
ALB_URL=$(kubectl get ingress laminar-frontend-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

helm upgrade -i laminar . -f laminar.yaml \
  --set frontend.env.nextauthUrl="http://$ALB_URL" \
  --set frontend.env.nextPublicUrl="http://$ALB_URL"
```

### Step 5: Access the Application

Open your browser and navigate to the ALB URL.

## Using a Custom Domain (Optional)

If you have a custom domain, skip Step 3-4 and install directly:

```bash
helm upgrade -i laminar . -f laminar.yaml \
  --set frontend.ingress.hostname="app.yourdomain.com" \
  --set frontend.env.nextauthUrl="https://app.yourdomain.com" \
  --set frontend.env.nextPublicUrl="https://app.yourdomain.com"
```

Then create a CNAME record pointing your domain to the ALB hostname.

## Verify Installation

Check that all pods are running:

```bash
kubectl get pods
```

Expected output (all pods should be `Running` or `1/1`):

```
NAME                                              READY   STATUS    AGE
laminar-app-server-xxx                            2/2     Running   5m
laminar-app-server-consumer-xxx                   1/1     Running   5m
laminar-clickhouse-0                              1/1     Running   5m
laminar-frontend-xxx                              1/1     Running   5m
laminar-postgres-0                                1/1     Running   5m
laminar-query-engine-xxx                          1/1     Running   5m
laminar-quickwit-control-plane-xxx                1/1     Running   5m
laminar-quickwit-indexer-0                        1/1     Running   5m
laminar-quickwit-janitor-xxx                      1/1     Running   5m
laminar-quickwit-metastore-xxx                    1/1     Running   5m
laminar-quickwit-searcher-0                       1/1     Running   5m
laminar-rabbitmq-0                                1/1     Running   5m
laminar-redis-xxx                                 1/1     Running   5m
```

## Troubleshooting

### Pods stuck in Pending

Check if EBS CSI driver is installed and storage class exists:

```bash
kubectl get storageclass
kubectl describe pod <pod-name>
```

### Pods stuck in Init state

Services are waiting for dependencies. Check which service is not ready:

```bash
kubectl logs <pod-name> -c wait-for-postgres
kubectl logs <pod-name> -c wait-for-redis
```

### Load Balancer not created

Verify AWS Load Balancer Controller is installed:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

## Next Steps

- See [CONFIGURATION.md](./CONFIGURATION.md) for production settings, secrets management, and S3 storage
- See [DEPENDENCIES.md](./DEPENDENCIES.md) for understanding service startup order
