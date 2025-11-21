# Quick Start Guide

This guide provides quick examples for common configuration scenarios.

## Basic Deployment

Deploy with default settings (all services on the same node group):

```bash
helm install laminar . -f values.yaml
```

## Scenario 1: Deploy to Multiple Node Groups

Create a `values-custom.yaml` file:

```yaml
# values-custom.yaml
global:
  nodeGroupName: "general"  # Default for all services

# Override for databases - use storage-optimized nodes
postgres:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: alpha.eksctl.io/nodegroup-name
            operator: In
            values:
            - storage-optimized

clickhouse:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: alpha.eksctl.io/nodegroup-name
            operator: In
            values:
            - storage-optimized

# Override for compute-intensive services
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

Deploy:

```bash
helm install laminar . -f values.yaml -f values-custom.yaml
```

## Scenario 2: ClickHouse with S3 Storage

Create a `values-s3.yaml` file:

```yaml
# values-s3.yaml
clickhouse:
  # Disable local persistence
  persistence:
    enabled: false
  
  # Enable S3-backed storage
  s3:
    enabled: true
    endpoint: "https://my-clickhouse-data.s3.us-east-1.amazonaws.com/"
    region: "us-east-1"
    # Use IAM role for credentials (recommended)
    useEnvironmentCredentials: true
    # Local cache for hot data
    cache:
      enabled: true
      maxSize: "50Gi"
```

Deploy:

```bash
helm install laminar . -f values.yaml -f values-s3.yaml
```

### Prerequisites for S3 Storage:

1. **Create S3 bucket**:
   ```bash
   aws s3 mb s3://my-clickhouse-data --region us-east-1
   ```

2. **Create IAM policy** (`clickhouse-s3-policy.json`):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject",
           "s3:ListBucket",
           "s3:GetBucketLocation"
         ],
         "Resource": [
           "arn:aws:s3:::my-clickhouse-data",
           "arn:aws:s3:::my-clickhouse-data/*"
         ]
       }
     ]
   }
   ```

3. **Attach policy to node IAM role** (for EC2 instances) or **create IRSA** (for EKS with pod-level IAM):
   ```bash
   # For EC2 node IAM role
   aws iam put-role-policy \
     --role-name <your-node-role> \
     --policy-name ClickHouseS3Access \
     --policy-document file://clickhouse-s3-policy.json
   ```

## Scenario 3: Different Storage Classes

Create a `values-storage.yaml` file:

```yaml
# values-storage.yaml

# PostgreSQL with io2 (high IOPS for transactional workload)
postgres:
  persistence:
    enabled: true
    storageClass: "io2-sc"
    size: "100Gi"

# RabbitMQ with gp3 (balanced)
rabbitmq:
  persistence:
    enabled: true
    storageClass: "gp3-sc"
    size: "10Gi"

# ClickHouse with S3 (cost-effective, scalable)
clickhouse:
  persistence:
    enabled: false
  s3:
    enabled: true
    endpoint: "https://my-clickhouse-data.s3.us-east-1.amazonaws.com/"
    region: "us-east-1"
    useEnvironmentCredentials: true
```

First, create the storage classes if needed:

```yaml
# storage-classes.yaml
---
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
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-sc
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

Deploy:

```bash
kubectl apply -f storage-classes.yaml
helm install laminar . -f values.yaml -f values-storage.yaml
```

## Scenario 4: Spot Instances for Stateless Services

Create a `values-spot.yaml` file:

```yaml
# values-spot.yaml

# Frontend can use spot instances
frontend:
  tolerations:
    - key: "node.kubernetes.io/instance-type"
      operator: "Equal"
      value: "spot"
      effect: "NoSchedule"
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: "node.kubernetes.io/instance-type"
            operator: In
            values:
            - spot

# App servers can use spot instances
appServer:
  tolerations:
    - key: "node.kubernetes.io/instance-type"
      operator: "Equal"
      value: "spot"
      effect: "NoSchedule"
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: "node.kubernetes.io/instance-type"
            operator: In
            values:
            - spot

# Databases MUST use on-demand instances
postgres:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: "node.kubernetes.io/instance-type"
            operator: NotIn
            values:
            - spot

clickhouse:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: "node.kubernetes.io/instance-type"
            operator: NotIn
            values:
            - spot
```

## Verification

Check pod placement:

```bash
# See which nodes pods are running on
kubectl get pods -o wide

# Check pod affinity/tolerations
kubectl describe pod <pod-name>

# For ClickHouse with S3, verify the configuration
kubectl exec -it clickhouse-0 -- cat /etc/clickhouse-server/config.d/storage_config.xml

# Check ClickHouse storage policy
kubectl exec -it clickhouse-0 -- clickhouse-client --query "SELECT * FROM system.disks"
kubectl exec -it clickhouse-0 -- clickhouse-client --query "SELECT * FROM system.storage_policies"
```

## Testing ClickHouse S3 Storage

Create a test table using the S3 storage policy:

```bash
# Connect to ClickHouse
kubectl exec -it clickhouse-0 -- clickhouse-client

# Create a test table with S3 storage
CREATE TABLE test_s3 (
    id UInt64,
    name String,
    created DateTime
) ENGINE = MergeTree()
ORDER BY id
SETTINGS storage_policy = 's3_main';

# Insert test data
INSERT INTO test_s3 VALUES (1, 'test', now());

# Verify data is stored
SELECT * FROM test_s3;

# Check which disk is being used
SELECT 
    table,
    disk_name,
    path 
FROM system.parts 
WHERE table = 'test_s3';
```

## Upgrading Existing Deployments

To upgrade an existing deployment with new configuration:

```bash
# Check what will change
helm diff upgrade laminar . -f values.yaml -f values-custom.yaml

# Apply the upgrade
helm upgrade laminar . -f values.yaml -f values-custom.yaml

# Watch the rollout
kubectl rollout status statefulset/clickhouse
kubectl rollout status deployment/frontend
```

## Troubleshooting

### Pods stuck in Pending

```bash
# Check events
kubectl describe pod <pod-name>

# Common issues:
# - Node selector doesn't match any nodes
# - Tolerations don't match node taints
# - Insufficient resources on matching nodes
```

### ClickHouse S3 connection issues

```bash
# Check ClickHouse logs
kubectl logs clickhouse-0

# Verify S3 config is mounted
kubectl exec clickhouse-0 -- cat /etc/clickhouse-server/config.d/storage_config.xml

# Test S3 access from pod
kubectl exec -it clickhouse-0 -- sh
# Inside the pod:
apk add aws-cli
aws s3 ls s3://my-clickhouse-data/
```

### Storage class not found

```bash
# List available storage classes
kubectl get storageclass

# If missing, create them
kubectl apply -f storage-classes.yaml
```

## Next Steps

- See [CONFIGURATION.md](./CONFIGURATION.md) for detailed documentation
- See [examples/](./examples/) directory for more configuration examples
- Refer to [ClickHouse S3 Storage Guide](https://clickhouse.com/docs/guides/separation-storage-compute) for advanced S3 configuration

## Support

For issues or questions:
- Check pod events: `kubectl describe pod <pod-name>`
- Check logs: `kubectl logs <pod-name>`
- Review Helm values: `helm get values laminar`

