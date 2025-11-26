# Quick Start Guide

Get Laminar running on your Kubernetes cluster in minutes.

## Prerequisites

- Kubernetes cluster (EKS recommended)
- Helm 3.x
- [AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) installed
- [EBS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) installed

## Installation

### Step 1: Customize Configuration

Copy and edit `laminar.yaml` with your settings:

- Set AWS credentials and S3 bucket names
- Set ClickHouse S3 bucket endpoint and region
- Set your availability zone(s)

### Step 2: Install with Customized Settings

The `--create-namespace` flag will automatically create the `laminar` namespace if it doesn't exist:

```bash
helm upgrade -i laminar . -f laminar.yaml --namespace laminar --create-namespace
```

### Step 3: Get the Load Balancer URL

Wait for the ALB to be provisioned (1-2 minutes), then get the URL:

```bash
kubectl get ingress frontend-alb -n laminar -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Step 4: Configure Frontend URLs

Update `laminar.yaml` with the ALB URL or upgrade directly:

```bash
ALB_URL=$(kubectl get ingress frontend-alb -n laminar -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

helm upgrade -i laminar . -f laminar.yaml --namespace laminar \
  --set secrets.data.NEXTAUTH_URL="http://$ALB_URL" \
  --set secrets.data.NEXTAUTH_PUBLIC_URL="http://$ALB_URL" \
  --set frontend.env.nextauthUrl="http://$ALB_URL" \
  --set frontend.env.nextPublicUrl="http://$ALB_URL"
```

### Step 5: Access the Application

Open your browser and navigate to the ALB URL.

## Using a Custom Domain (Optional)

If you have a custom domain, skip Step 3-4 and install directly:

```bash
helm upgrade -i laminar . -f laminar.yaml --namespace laminar --create-namespace \
  --set frontend.ingress.hostname="app.yourdomain.com" \
  --set secrets.data.NEXTAUTH_URL="https://app.yourdomain.com" \
  --set secrets.data.NEXTAUTH_PUBLIC_URL="https://app.yourdomain.com" \
  --set frontend.env.nextauthUrl="https://app.yourdomain.com" \
  --set frontend.env.nextPublicUrl="https://app.yourdomain.com"
```

Then create a CNAME record pointing your domain to the ALB hostname.

## Verify Installation

Check that all pods are running:

```bash
kubectl get pods -n laminar
```

Expected output (all pods should be `Running` or `1/1`):

```
NAME                                      READY   STATUS    AGE
app-server-xxx                            2/2     Running   5m
app-server-consumer-xxx                   1/1     Running   5m
clickhouse-0                              1/1     Running   5m
frontend-xxx                              1/1     Running   5m
postgres-0                                1/1     Running   5m
query-engine-xxx                          1/1     Running   5m
quickwit-control-plane-xxx                1/1     Running   5m
quickwit-indexer-0                        1/1     Running   5m
quickwit-janitor-xxx                      1/1     Running   5m
quickwit-metastore-xxx                    1/1     Running   5m
quickwit-searcher-0                       1/1     Running   5m
rabbitmq-0                                1/1     Running   5m
redis-xxx                                 1/1     Running   5m
```

## Troubleshooting

### Pods stuck in Pending

Check if EBS CSI driver is installed and storage class exists:

```bash
kubectl get storageclass
kubectl describe pod <pod-name> -n laminar
```

### Pods stuck in Init state

Services are waiting for dependencies. Check which service is not ready:

```bash
kubectl logs <pod-name> -n laminar -c wait-for-postgres
kubectl logs <pod-name> -n laminar -c wait-for-redis
```

### Load Balancer not created

Verify AWS Load Balancer Controller is installed:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

## Next Steps

- See [CONFIGURATION.md](./CONFIGURATION.md) for production settings, secrets management, and S3 storage
- See [DEPENDENCIES.md](./DEPENDENCIES.md) for understanding service startup order
