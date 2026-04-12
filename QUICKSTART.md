# Quick Start Guide

Get Laminar running on your Kubernetes cluster in minutes.

## Prerequisites

- Kubernetes cluster (EKS or GKE recommended)
- Helm 3.x
- **AWS**: [AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) and [EBS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) installed
- **GCP**: GCE Ingress and Persistent Disk CSI Driver (usually pre-installed on GKE)

> **Note on Namespaces:** By default, all resources are created in the `default` namespace. If you prefer using a custom namespace (e.g., `laminar`), add `--namespace laminar --create-namespace` to all `helm` commands and `-n laminar` to all `kubectl` commands in this guide.

## Installation

### Step 1: Customize Configuration

Edit `laminar.yaml` and replace **all** placeholder values with your actual settings:

- Set `global.cloudProvider` to `aws` or `gcp`
- Set your cloud credentials (AWS keys, Gemini API key)
- Replace `<bucket-name>` and `<region>` in `clickhouse.s3` with your real S3 bucket and region
- Replace `your-bucket-name` and `<region>` in `quickwit.s3` with your real S3 bucket and region
- Set your availability zone(s) in `storage.storageClass.zones` (required for AWS EBS)

> **Important:** Angle-bracket placeholders like `<region>` will be interpreted as XML tags in the ClickHouse config and cause pods to crash. Make sure every placeholder is replaced with a real value.

### Step 2: Install with Customized Settings

Install Laminar with your customized configuration:

```bash
helm upgrade -i laminar ./charts/laminar -f laminar.yaml
```

### Step 3: Get the Load Balancer URL

Wait for the load balancer to be provisioned (1-2 minutes), then get the URL:

**For AWS (ALB):**
```bash
kubectl get ingress laminar-frontend-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
Note: The URL will be available nearly immediately, but the load balancer takes a few minutes to become available.

**For GCP (GKE LoadBalancer Service):**
```bash
kubectl get svc laminar-frontend-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Step 4: Configure Frontend URLs

Update `laminar.yaml` with the URL/IP or upgrade directly:

**For AWS:**
```bash
URL=$(kubectl get ingress laminar-frontend-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
helm upgrade -i laminar ./charts/laminar -f laminar.yaml \
  --set frontend.env.nextauthUrl="http://$URL" \
  --set frontend.env.nextPublicUrl="http://$URL"
```

**For GCP:**
```bash
IP=$(kubectl get svc laminar-frontend-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
helm upgrade -i laminar ./charts/laminar -f laminar.yaml \
  --set frontend.env.nextauthUrl="http://$IP" \
  --set frontend.env.nextPublicUrl="http://$IP"
```

### Step 5: Access the Application

Open your browser and navigate to the URL or IP retrieved in Step 4.

### Step 6: Configure the SDK to point at the app-server URL

**For AWS:**
```bash
LMNR_BASE_URL=$(kubectl get svc laminar-app-server-load-balancer -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')\
    && echo "http://$LMNR_BASE_URL" # or https
```

**For GCP:**
```bash
LMNR_BASE_URL=$(kubectl get svc laminar-app-server-load-balancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\
    && echo "http://$LMNR_BASE_URL" # or https
```

You can now use this URL as the `baseUrl` in the SDK when initializing `Laminar` and/or `LaminarClient`.

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

Check if the CSI driver is installed and storage class exists:

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

Verify the correct `cloudProvider` is set in `laminar.yaml`. 

**For AWS**, verify the Load Balancer Controller is installed:
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

**For GCP**, verify the service status:
```bash
kubectl describe svc laminar-frontend-service
```

## Next Steps

- See [CONFIGURATION.md](./CONFIGURATION.md) for production settings, secrets management, and S3 storage
- See [DEPENDENCIES.md](./DEPENDENCIES.md) for understanding service startup order
