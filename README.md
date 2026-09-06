# vCluster Auto Nodes GCP

**td;dr**: I just need a `vcluster.yaml` to get started:

```yaml
# vcluster.yaml
controlPlane:
  service:
    spec:
     type: LoadBalancer
privateNodes:
  enabled: true
  autoNodes:
  - provider: gcp-compute
    dynamic:
    - name: gcp-cpu-nodes
      nodeTypeSelector:
      - property: instance-type
        operator: In
        values: ["e2-medium", "e2-standard-2", "e2-standard-4"]
```

...plus a `NetworkEnvironment` for the provider, which an administrator creates once. See
[Step 3](#step-3-create-a-network-environment).

## Overview

Terraform modules for provisioning **Auto Nodes on GCP**.  
These modules dynamically create Compute Engine instances as vCluster Private Nodes, powered by **Karpenter**.

### Key Features

- **Dynamic provisioning** – Nodes automatically scale up or down based on pod requirements  
- **Multi-cloud support** – Run tenant cluster nodes across GCP, AWS, Azure, on-premises, or bare metal  
  - CSI configuration in multi-cloud environments requires manual setup.
- **Cost optimization** – Provision only the resources you actually need  
- **Simple configuration** – Define node requirements directly in your `vcluster.yaml`  

This quickstart **NodeProvider** creates one VPC per **NetworkEnvironment**. A network environment
is shared: every tenant cluster whose nodes bind to it gets those nodes in the same VPC. Create
several environments to separate tenant clusters from each other, or to span regions.

> Requires vCluster Platform **4.13 or newer**. For 4.12 and older, use the `v0.1.x` tags of this
> repository and see [Upgrading from Platform 4.12](#upgrading-from-platform-412).

---

## What gets created

### [Network environment](./environment/infrastructure) – once per `NetworkEnvironment`

- A dedicated VPC  
- Public subnets in two zones  
- Private subnets in two zones  
- A Cloud NAT for private subnets  
- Firewall rules for worker nodes  
- A service account for worker nodes  
  - Permissions depend on whether CCM and CSI are enabled  

### [Nodes](./node/) – once per node

- Compute Engine instances using the selected `machine-type`, attached to private subnets  
  - If no default zone is set and `privateNodes.autoNodes[*].nodeTypeSelector` does not contain a `zone`, nodes may be spread across available zones in the selected region.  

### [Tenant cluster add-ons](./addons) – optional, run by you

- Cloud Controller Manager for node initialization and automatic LoadBalancer creation  
- GCP Persistent Disk CSI driver with a default storage class  
  - The default storage class does **not** enforce allowed topologies (important in multi-cloud setups). You can provide your own.  

These used to be applied by the node provider itself. Platform 4.13 removed the stage that did
that, because a shared network environment has no single tenant cluster to deploy into. The
manifests are unchanged; you now apply them per tenant cluster. See [addons/README.md](./addons/README.md).

## Getting started

### Prerequisites

1. Access to a GCP account
2. A control plane cluster, preferrably on GKE to use Workload Identity
3. vCluster Platform 4.13 or newer running in the control plane cluster. [Get started](https://www.vcluster.com/docs/platform/install/quick-start-guide)
4. Ensure the [Cloud Resource Manager API](https://cloud.google.com/resource-manager/docs) is enabled in your GCP account
5. (optional) The [vCluster CLI](https://www.vcluster.com/docs/vcluster/#deploy-vcluster)
6. (optional) Authenticate the vCluster CLI `vcluster platform login $YOUR_PLATFORM_HOST`

### Setup

#### Step 1: Configure Node Provider

Define your GCP Node Provider in the vCluster Platform. This provider manages the lifecycle of Compute instances.

In the vCluster Platform UI, navigate to "Infra > Nodes", click on "Create Node Provider" and then use "GCP Compute".
Specify a **Project** in which all resources will be created, and a **default region**. You can
optionally set a **default zone**.

Project and region have to be set on the node provider or on the network environment, not on a node
type: the infrastructure template is never passed node type properties. See
[Where properties go](#where-properties-go).

[docs/node_provider.example.yaml](./docs/node_provider.example.yaml) is the equivalent as YAML.

#### Step 2: Authenticate the Node Provider

Auto Nodes supports two authentication methods for GCP resources. **Workload Identity is strongly recommended** for production use.

##### Option A: Workload Identity (Recommended)

[Configure GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity) to grant the vCluster control plane permissions to manage Compute Instances.
Next, create [an IAM role](./docs/auto_nodes_role.yaml) for your organization

```bash
gcloud iam roles create vClusterPlatformAutoNodes --organization=$ORG_ID --file=./auto_nodes_role.yaml
```

or for your project

```bash
gcloud iam roles create vClusterPlatformAutoNodes --project=$PROJECT_ID --file=./auto_nodes_role.yaml
```

Assign the role you just created to your IAM principal to authenticate the terraform provider.

##### Option B: Manual secrets

If Workload Identity is not available, use a kubernetes secret with static credentials to authenticate against GCP.
You can create this secret from the vCluster Platform UI by choosing "specify credentials inline" in the Quickstart setup, or manually later on:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gcp-credentials
  namespace: vcluster-platform
  labels:
    terraform.vcluster.com/provider: "gcp-compute" # This has to match your provider name
stringData:
    GOOGLE_CREDENTIALS: |
      { "..." }
EOF
```

This uses a [service account key](https://cloud.google.com/iam/docs/service-account-creds).
Ensure the Service Account has at least the permissions outlined in [the auto nodes role](./docs/auto_nodes_role.yaml).

#### Step 3: Create a network environment

The network environment is the VPC the nodes go into. It is cluster scoped and shared, so an
administrator creates it once for the provider rather than one appearing per tenant cluster. Until
one exists, the provider places no nodes and node claims report `NetworkEnvironmentNotAvailable`.

Create it in the UI under "Infra > Nodes > Network Environments", or as YAML:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: management.loft.sh/v1
kind: NetworkEnvironment
metadata:
  name: gcp-compute-us-east1
  annotations:
    # node claims of this provider that do not name an environment bind here
    machines.vcluster.com/is-default-environment: "true"
spec:
  providerRef: gcp-compute
  properties:
    vcluster.com/vpc-cidr: "10.10.0.0/16"
EOF
```

Wait for its status to reach `Available` before creating tenant clusters against it. More examples,
including a second environment in another region, in
[docs/network_environment.example.yaml](./docs/network_environment.example.yaml).

Projects can be restricted to a subset of environments with `spec.allowedNetworkEnvironments`.

#### Step 4: Create a tenant cluster

This vcluster.yaml file defines a private-node tenant cluster with Auto Nodes enabled. It exposes
the control plane through a LoadBalancer on the GKE control plane cluster. This is required for
individual Compute Instances to join the cluster.

```yaml
# vcluster.yaml
controlPlane:
  service:
    spec:
     type: LoadBalancer
privateNodes:
  enabled: true
  autoNodes:
  - provider: gcp-compute
    dynamic:
    - name: gcp-cpu-nodes
      nodeTypeSelector:
      - property: instance-type
        operator: In
        values: ["e2-medium", "e2-standard-2", "e2-standard-4"]
      limits:
        cpu: "100"
        memory: "200Gi"
```

Create the tenant cluster through the vCluster Platform UI or the vCluster CLI:

 `vcluster platform create vcluster gcp-private-nodes -f ./vcluster.yaml --project default`

#### Step 5: Deploy the add-ons (optional)

If you want the GCP Cloud Controller Manager (node initialization, LoadBalancer services) or the
Persistent Disk CSI driver in this tenant cluster, apply [addons](./addons) against it. If you do
not want them, set `vcluster.com/ccm-enabled` and `vcluster.com/csi-enabled` to `false` on the node
provider so the nodes are not granted permissions nothing uses.

## Advanced configuration

### Where properties go

Properties are merged from several places, and which template sees which set differs. This matters
because the same key can be a no-op in one place and take effect in another.

| Template | Sees properties from |
| --- | --- |
| [environment/infrastructure](./environment/infrastructure) | NodeProvider, NetworkEnvironment |
| [node](./node) | NodeProvider, NodeType, NetworkEnvironment, NodeClaim (`privateNodes.autoNodes[*].properties` and node pool properties) |

So anything that shapes the VPC has to be set on the **NodeProvider** or the **NetworkEnvironment**.
Setting it under `privateNodes.autoNodes[*].properties` in a tenant cluster's `vcluster.yaml`
reaches the node template only, and silently does nothing to the network.

### Configuration options

| Property                           | Default        | Set on                          | Description                                                                                     |
| ---------------------------------- | -------------- | ------------------------------- | ----------------------------------------------------------------------------------------------- |
| `project`                          | required       | NodeProvider or NetworkEnvironment | GCP project all resources are created in.                                                      |
| `region`                           | required       | NodeProvider or NetworkEnvironment | GCP region the VPC and the nodes are placed in.                                                |
| `vcluster.com/vpc-cidr`            | `10.10.0.0/16` | NodeProvider or NetworkEnvironment | VPC CIDR range. Give each environment its own range so tenant clusters can span them.          |
| `vcluster.com/subnet-prefix`       | `24`           | NodeProvider or NetworkEnvironment | Prefix length of the public and private subnets carved out of the VPC CIDR.                    |
| `vcluster.com/ccm-enabled`         | `true`         | NodeProvider or NetworkEnvironment | Grants the node service account the IAM roles the CCM needs. Does not deploy it, see [addons](./addons). |
| `vcluster.com/csi-enabled`         | `true`         | NodeProvider or NetworkEnvironment | Grants the node service account the IAM roles the CSI driver needs. Does not deploy it.        |
| `vcluster.com/network-environment` | provider default | NodeProvider, NodeType or node pool | Name of the NetworkEnvironment the nodes bind to.                                            |
| `zone`                             | unset          | NodeProvider, NodeType or node pool | Comma-separated zones the nodes may land in. Unset spreads them over the region.              |
| `instance-type`                    | required       | NodeType                        | Compute Engine machine type.                                                                     |

`vcluster.com/ccm-lb-enabled` is no longer a platform property. It is the `ccm_lb_enabled` variable
of the [addons](./addons) module.

### Selecting a network environment

A tenant cluster uses the provider's default environment unless it names another one:

```yaml
privateNodes:
  enabled: true
  autoNodes:
  - provider: gcp-compute
    properties:
      vcluster.com/network-environment: gcp-compute-europe-north2
    dynamic:
    - name: gcp-cpu-nodes
      nodeTypeSelector:
      - property: instance-type
        operator: In
        values: ["e2-medium", "e2-standard-2", "e2-standard-4"]
```

## Example

A second, isolated network environment with its own CIDR, no CCM and no CSI:

```yaml
apiVersion: management.loft.sh/v1
kind: NetworkEnvironment
metadata:
  name: gcp-compute-isolated
spec:
  providerRef: gcp-compute
  properties:
    vcluster.com/vpc-cidr: "10.20.0.0/16"
    vcluster.com/ccm-enabled: "false"
    vcluster.com/csi-enabled: "false"
```

...and a tenant cluster placed into it:

```yaml
controlPlane:
  service:
    spec:
     type: LoadBalancer
privateNodes:
  enabled: true
  autoNodes:
  - provider: gcp-compute
    properties:
      vcluster.com/network-environment: gcp-compute-isolated
    dynamic:
    - name: gcp-cpu-nodes
      nodeTypeSelector:
      - property: instance-type
        operator: In
        values: ["e2-medium", "e2-standard-2", "e2-standard-4"]
```

## Security considerations

> **_NOTE:_** When running [Cloud Controller Manager (CCM)](https://kubernetes.io/docs/concepts/architecture/cloud-controller/) and [Container Storage Interface (CSI)](https://kubernetes.io/blog/2019/01/15/container-storage-interface-ga/) with Auto Nodes, permissions are granted through user assigned managed identity.
**This means all worker nodes inherit the same permissions as CCM and CSI.**
As a result, **any pod in the cluster could potentially access the same cloud permissions**.
Refer to the full [list of permissions](environment/infrastructure/iam.tf) for details.

Cluster administrators should be aware of the following:

- **Shared permissions** – all pods running in a **host network** may gain the same access level as CCM and CSI.  
- **Shared network** – tenant clusters bound to the same network environment share a VPC, and the
  `allow-internal` firewall rule permits traffic between all of its subnets. Nodes of one tenant
  cluster can reach nodes of another. Give tenant clusters that must not reach each other separate
  network environments.  
- **Mitigation** – cluster administrators can set `vcluster.com/ccm-enabled` and
  `vcluster.com/csi-enabled` to `false`.  
  In that case, virtual machines will not be granted additional permissions.  
  However, responsibility for deploying and securely configuring CCM and CSI will then fall to the cluster administrator.  

> **_NOTE:_** Security-sensitive environments should carefully review which permissions are granted to clusters and consider whether CCM/CSI should be disabled and managed manually.

## Limitations

### Hybrid-cloud and multi-cloud

When running a tenant cluster across multiple providers, some additional configuration is required:

- **CSI drivers** – Install and configure the appropriate CSI driver for GCP cloud provider.  
- **StorageClasses** – Use `allowedTopologies` to restrict provisioning to valid zones/regions.  
- **NodePools** – Add matching zone labels so the scheduler can place pods on nodes with storage in the same zone.  
- **CIDRs** – Give each network environment a non-overlapping `vcluster.com/vpc-cidr`.  

For details on multi-cloud setup, see the [Deploy](https://www.vcluster.com/docs/vcluster/deploy/worker-nodes/private-nodes/auto-nodes/quick-start-templates#deploy) and [Limits](https://www.vcluster.com/docs/vcluster/deploy/worker-nodes/private-nodes/auto-nodes/quick-start-templates#hybrid-cloud-and-multi-cloud) vCluster documentation.

#### Example: GCP PD Disk StorageClass with zones

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gcp-standard
provisioner: pd.csi.storage.gke.io
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: pd-standard
allowedTopologies:
  - matchLabelExpressions:
      - key: topology.gke.io/zone
        values: ["us-central1-a"]
```

### Region changes

Changing the region of an existing network environment is not supported, and a region set per
tenant cluster no longer moves its VPC. To use another region, create a second network environment
with `region` set on it and bind tenant clusters to that one.

### Dynamic nodes `Limit`

When editing the limits property of dynamic nodes, any nodes that already exceed the new limit will **not** be removed automatically.
Administrators are responsible for manually scaling down or deleting the excess nodes.

## Upgrading from Platform 4.12

Platform 4.13 renamed `NodeEnvironment` to `NetworkEnvironment` and reworked what it is. The
`v0.1.x` tags of this repository work with 4.12 and older; `v0.2.0` and newer require 4.13.

What changes for you:

- **Update the NodeProvider.** `spec.terraform.nodeEnvironmentTemplate` is now
  `networkEnvironmentTemplate`, and its `kubernetes` stage is gone. The old field name is not
  accepted or aliased; it is dropped silently, leaving a provider that cannot place nodes.
- **Create a NetworkEnvironment.** Environments are no longer created per tenant cluster. Nothing
  provisions until one exists for the provider. See [Step 3](#step-3-create-a-network-environment).
- **Move CCM and CSI.** They are no longer deployed by the provider. See [addons](./addons).
- **Move properties.** Anything the VPC depends on moves from `privateNodes.autoNodes[*].properties`
  in each tenant cluster's `vcluster.yaml` to the NodeProvider or the NetworkEnvironment. See
  [Where properties go](#where-properties-go).
- **Expect a fresh apply.** The platform stores this state under new workspace and secret names, so
  4.13 starts from an empty state and provisions a new VPC rather than adopting the ones 4.12
  created. The old VPCs, NATs, firewall rules, service accounts and IAM roles are left behind and
  have to be removed by hand once the tenant clusters that used them are gone.
