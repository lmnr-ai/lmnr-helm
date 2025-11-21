# Helm Chart Configuration Examples

This directory contains example configuration files demonstrating common deployment scenarios for the Laminar Helm chart.

## Available Examples

### 1. Multiple Node Groups (`multiple-node-groups.yaml`)
Deploy different services to different node groups based on their resource requirements.

**Use case:** Optimize costs by running compute-intensive and storage-intensive workloads on specialized node types.

**Deploy:**
```bash
helm install laminar .. -f ../values.yaml -f multiple-node-groups.yaml
```

### 2. ClickHouse with S3 Storage (`clickhouse-s3-storage.yaml`)
Configure ClickHouse to use S3 for data storage, enabling separation of storage and compute.

**Use case:** Lower storage costs and scale storage independently from compute resources.

**Prerequisites:**
- Create S3 bucket
- Configure IAM permissions (see [CONFIGURATION.md](../CONFIGURATION.md))

**Deploy:**
```bash
helm install laminar .. -f ../values.yaml -f clickhouse-s3-storage.yaml
```

### 3. Mixed Storage Classes (`mixed-storage-classes.yaml`)
Use different storage classes (io2, gp3, S3) for different services based on their performance requirements.

**Use case:** Optimize cost vs performance by matching storage type to workload characteristics.

**Prerequisites:**
- Ensure storage classes exist in your cluster

**Deploy:**
```bash
helm install laminar .. -f ../values.yaml -f mixed-storage-classes.yaml
```

### 4. Spot Instances (`spot-instances.yaml`)
Run stateless services on spot instances for cost savings while keeping stateful services on reliable on-demand instances.

**Use case:** Reduce costs by up to 90% for stateless workloads.

**Prerequisites:**
- Spot instance node groups configured with appropriate taints

**Deploy:**
```bash
helm install laminar .. -f ../values.yaml -f spot-instances.yaml
```

### 5. Multi-Zone Deployment (`multi-zone-deployment.yaml`)
Spread replicas across multiple availability zones for high availability.

**Use case:** Protect against availability zone failures.

**Prerequisites:**
- Cluster spans multiple availability zones
- Storage classes use WaitForFirstConsumer binding mode

**Deploy:**
```bash
helm install laminar .. -f ../values.yaml -f multi-zone-deployment.yaml
```

## Combining Examples

You can combine multiple example files to create more complex configurations:

```bash
# Combine spot instances + multi-zone deployment
helm install laminar .. \
  -f ../values.yaml \
  -f spot-instances.yaml \
  -f multi-zone-deployment.yaml

# Combine multiple node groups + mixed storage
helm install laminar .. \
  -f ../values.yaml \
  -f multiple-node-groups.yaml \
  -f mixed-storage-classes.yaml
```

## Customizing Examples

These examples are templates. Before deploying:

1. **Review and update placeholder values**:
   - S3 bucket names
   - Node group names
   - Storage class names
   - Region names

2. **Adjust resource limits** based on your workload

3. **Test in a development environment** first

## Example Workflow

### 1. Copy an example to create your custom configuration
```bash
cp examples/clickhouse-s3-storage.yaml my-custom-values.yaml
```

### 2. Edit the file to match your environment
```bash
vim my-custom-values.yaml
# Update bucket names, regions, etc.
```

### 3. Validate your configuration
```bash
helm template laminar . -f values.yaml -f my-custom-values.yaml > rendered.yaml
kubectl apply --dry-run=client -f rendered.yaml
```

### 4. Deploy
```bash
helm install laminar . -f values.yaml -f my-custom-values.yaml
```

### 5. Verify deployment
```bash
kubectl get pods -o wide
kubectl describe pod <pod-name>
```

## Verification Commands

After deploying, verify your configuration:

### Check node placement
```bash
# See which nodes pods are running on
kubectl get pods -o wide

# Check specific pod's node affinity
kubectl describe pod <pod-name> | grep -A 10 "Node-Selectors\|Tolerations\|Affinity"
```

### Check storage configuration
```bash
# List persistent volume claims
kubectl get pvc

# Check storage class
kubectl get pvc <pvc-name> -o jsonpath='{.spec.storageClassName}'
```

### Verify ClickHouse S3 configuration
```bash
# Check storage config is mounted
kubectl exec clickhouse-0 -- cat /etc/clickhouse-server/config.d/storage_config.xml

# Verify S3 disks and policies
kubectl exec clickhouse-0 -- clickhouse-client --query "SELECT * FROM system.disks"
kubectl exec clickhouse-0 -- clickhouse-client --query "SELECT * FROM system.storage_policies"
```

## Troubleshooting

### Pods stuck in Pending
```bash
kubectl describe pod <pod-name>
```
Common issues:
- Node selector doesn't match any nodes
- Tolerations don't match node taints
- Insufficient resources

### Storage issues
```bash
# Check storage class exists
kubectl get storageclass

# Check PVC status
kubectl get pvc
kubectl describe pvc <pvc-name>
```

### ClickHouse S3 connection issues
```bash
# Check ClickHouse logs
kubectl logs clickhouse-0

# Verify IAM permissions
kubectl exec -it clickhouse-0 -- sh
# Inside pod: test S3 access
```

## Additional Resources

- [CONFIGURATION.md](../CONFIGURATION.md) - Detailed configuration documentation
- [QUICKSTART.md](../QUICKSTART.md) - Quick start guide with step-by-step instructions
- [values.yaml](../values.yaml) - Full configuration options reference

## Contributing

To add a new example:

1. Create a descriptively-named YAML file in this directory
2. Add clear comments explaining the use case and prerequisites
3. Update this README with the new example
4. Test the example in a real cluster

