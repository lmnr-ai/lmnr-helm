# Advanced Configuration Guide

This guide covers advanced configuration options for the Laminar Helm chart, including node placement strategies and storage configurations.

## Table of Contents

- [Node Placement and Scheduling](#node-placement-and-scheduling)
- [Storage Configuration](#storage-configuration)
- [ClickHouse S3-Backed Storage](#clickhouse-s3-backed-storage)
- [Examples](#examples)

## Node Placement and Scheduling

The Helm chart supports flexible node placement strategies for all services using Kubernetes node selectors, affinities, and tolerations.

### Configuration Structure

Each service (frontend, appServer, appServerConsumer, queryEngine, postgres, clickhouse, redis, rabbitmq) supports the following node scheduling configuration:

```yaml
<service>:
  # Simple key-value node selector
  nodeSelector:
    disktype: ssd
    region: us-east-1
  
  # Advanced affinity rules
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: alpha.eksctl.io/nodegroup-name
            operator: In
            values:
            - my-nodegroup
  
  # Tolerations for tainted nodes
  tolerations:
    - key: "workload-type"
      operator: "Equal"
      value: "database"
      effect: "NoSchedule"
```

### Global Defaults

You can set default node scheduling configuration in the `global` section:

```yaml
global:
  nodeGroupName: "general-purpose"  # Legacy: creates default affinity
  nodeSelector:
    region: us-east-1
  affinity: {}
  tolerations: []
```

Service-specific configurations override global defaults.

### Use Cases

#### 1. Deploy to Different Node Groups

```yaml
# Compute-intensive services
appServer:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: alpha.eksctl.io/nodegroup-name
            operator: In
            values:
            - compute-nodegroup

# Storage-intensive services
postgres:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: alpha.eksctl.io/nodegroup-name
            operator: In
            values:
            - storage-nodegroup
```

#### 2. Use Spot Instances

```yaml
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
```

#### 3. Multi-Zone Deployment

```yaml
postgres:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values:
              - postgres
          topologyKey: topology.kubernetes.io/zone
```

## Storage Configuration

### Per-Service Storage Classes

PostgreSQL, ClickHouse, and RabbitMQ now support individual storage class configuration:

```yaml
postgres:
  persistence:
    enabled: true
    storageClass: "io2"  # High IOPS for PostgreSQL
    size: "100Gi"

rabbitmq:
  persistence:
    enabled: true
    storageClass: "gp3"  # Balanced performance
    size: "10Gi"

clickhouse:
  persistence:
    enabled: true
    storageClass: "gp3"  # Or use S3 (see below)
    size: "50Gi"
```

### Available AWS EBS Storage Classes

- **gp3** (General Purpose SSD): Balanced price/performance, default for most workloads
- **gp2** (General Purpose SSD): Legacy, being replaced by gp3
- **io1/io2** (Provisioned IOPS SSD): High-performance, low-latency workloads
- **st1** (Throughput Optimized HDD): Big data, data warehouses
- **sc1** (Cold HDD): Infrequently accessed data

### Creating Custom Storage Classes

Example for io2:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: io2-sc
provisioner: kubernetes.io/aws-ebs
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

## ClickHouse S3-Backed Storage

ClickHouse supports separation of storage and compute using S3 as the storage backend. This provides:

- **Cost Efficiency**: S3 storage is cheaper than EBS volumes
- **Scalability**: Independent scaling of storage and compute
- **Durability**: S3's built-in replication and durability

### Configuration

```yaml
clickhouse:
  enabled: true
  # Disable local persistence when using S3
  persistence:
    enabled: false
  
  # Enable S3 storage
  s3:
    enabled: true
    # S3 bucket endpoint
    endpoint: "https://my-clickhouse-bucket.s3.us-east-1.amazonaws.com/"
    # S3 region
    region: "us-east-1"
    
    # Option 1: Use explicit credentials (not recommended for production)
    accessKeyId: "YOUR_ACCESS_KEY_ID"
    secretAccessKey: "YOUR_SECRET_ACCESS_KEY"
    useEnvironmentCredentials: false
    
    # Option 2: Use IAM role / environment credentials (recommended)
    # useEnvironmentCredentials: true
    
    # Local cache for frequently accessed data
    cache:
      enabled: true
      path: "/var/lib/clickhouse/disks/s3_cache/"
      maxSize: "50Gi"  # Adjust based on your needs
    
    # Metadata path
    metadataPath: "/var/lib/clickhouse/disks/s3_disk/"
```

### IAM Permissions for S3 Storage

When using S3-backed storage with `useEnvironmentCredentials: true`, ensure your Kubernetes service account or EC2 instance has the following IAM permissions:

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
        "arn:aws:s3:::my-clickhouse-bucket",
        "arn:aws:s3:::my-clickhouse-bucket/*"
      ]
    }
  ]
}
```

### How It Works

The ClickHouse S3 configuration creates a storage policy that:

1. Stores data in S3 instead of local disks
2. Maintains a local cache for frequently accessed data
3. Keeps metadata locally for fast query planning

Based on the [official ClickHouse guide](https://clickhouse.com/docs/guides/separation-storage-compute).

### Cache Size Considerations

The local cache size should be based on:
- **Working Set Size**: Data frequently accessed in queries
- **Query Patterns**: More complex queries benefit from larger caches
- **Node Storage**: Available disk space on Kubernetes nodes

Recommended starting point: 10-20% of your total data size.

### Important Notes

⚠️ **Do NOT configure AWS/GCS lifecycle policies on the S3 bucket**. This is not supported and could lead to broken tables.

## Examples

See the [examples/](./examples/) directory for comprehensive examples including:

1. Deploying different services to different node groups
2. ClickHouse with S3-backed storage
3. Mix of storage classes for different services
4. Spot instances with tolerations
5. Multi-zone deployment

## Best Practices

### Node Placement

1. **Stateful Services**: Use dedicated node groups with stable nodes (not spot instances)
2. **Stateless Services**: Can use spot instances with appropriate tolerations
3. **Resource Isolation**: Separate compute-intensive and storage-intensive workloads
4. **Multi-AZ**: Use pod anti-affinity to spread replicas across availability zones

### Storage

1. **PostgreSQL**: Use io2 or gp3 with higher IOPS for production
2. **RabbitMQ**: gp3 is usually sufficient
3. **ClickHouse**: 
   - For hot data / high query performance: io2 or gp3
   - For cost efficiency / separation of compute: S3-backed storage
4. **Cache Size** (for S3-backed ClickHouse): Start with 50Gi and monitor query performance

### Security

1. Always use IAM roles with `useEnvironmentCredentials: true` instead of hardcoding credentials
2. Use Kubernetes service accounts with IAM role annotations (IRSA on EKS)
3. Enable encryption at rest for both EBS volumes and S3 buckets
4. Use separate S3 buckets for ClickHouse data and other application data

## Troubleshooting

### ClickHouse S3 Issues

**Problem**: ClickHouse can't connect to S3

**Solutions**:
- Verify S3 endpoint URL is correct
- Check IAM permissions
- Ensure network policies allow S3 access
- Check ClickHouse logs: `kubectl logs clickhouse-0 -n <namespace>`

**Problem**: Poor query performance with S3

**Solutions**:
- Increase cache size
- Ensure cache is enabled
- Optimize table engines and partition keys
- Consider hybrid approach: hot data on EBS, cold data on S3

### Node Scheduling Issues

**Problem**: Pods are pending with "FailedScheduling" error

**Solutions**:
- Check node selectors match available nodes
- Verify tolerations match node taints
- Ensure requested resources are available
- Check `kubectl describe pod <pod-name>` for details

## Migration Guide

### Migrating ClickHouse from EBS to S3

1. **Backup your data**: Use ClickHouse BACKUP command
2. **Create S3 bucket and configure IAM**
3. **Update values.yaml**:
   ```yaml
   clickhouse:
     persistence:
       enabled: false
     s3:
       enabled: true
       # ... S3 configuration
   ```
4. **Deploy updated chart**: `helm upgrade ...`
5. **Restore data**: Use ClickHouse RESTORE command or let application repopulate

### Changing Storage Classes

1. **Backup your data**
2. **Create new storage class** if needed
3. **Update values.yaml** with new storageClass name
4. **Backup StatefulSet manifests**: `kubectl get sts <name> -o yaml > backup.yaml`
5. **Delete StatefulSet but keep PVCs**: `kubectl delete sts <name> --cascade=orphan`
6. **Update the chart**: `helm upgrade ...`
7. **Migrate data** from old PVCs to new PVCs
8. **Delete old PVCs** after verification

⚠️ **Note**: StatefulSets don't support changing storage class in-place. You need to migrate data manually.

## Additional Resources

- [Kubernetes Node Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Kubernetes Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [ClickHouse S3 Storage](https://clickhouse.com/docs/guides/separation-storage-compute)
- [AWS EBS Volume Types](https://aws.amazon.com/ebs/volume-types/)

