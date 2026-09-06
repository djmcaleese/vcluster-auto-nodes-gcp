# Tenant cluster add-ons

The GCP Cloud Controller Manager and the GCP Persistent Disk CSI driver, for a tenant cluster
whose nodes come from this node provider.

## Why this is a separate module

Up to Platform 4.12 these manifests were applied by the node provider itself, through the
`kubernetes` stage of `spec.terraform.nodeEnvironmentTemplate`. Platform 4.13 renamed
`NodeEnvironment` to `NetworkEnvironment`, made it cluster scoped and shared between tenant
clusters, and removed the `kubernetes` stage outright - a shared environment has no single tenant
cluster to deploy into and is handed no kubeconfig. The manifests themselves are unchanged; only
their inputs are now explicit variables instead of `var.vcluster.*`.

So this is something you run yourself, once per tenant cluster that wants it.

## Usage

`network_name` and `subnet_name` are outputs of the NetworkEnvironment's infrastructure stage.
Read them off the environment, or from the GCP console.

```bash
vcluster connect my-cluster --project default --print > ./kubeconfig.yaml

terraform init
terraform apply \
  -var kubeconfig=./kubeconfig.yaml \
  -var vcluster_name=my-cluster \
  -var node_provider_name=gcp-compute \
  -var network_name=vcluster-network-1a2b3c4d \
  -var subnet_name=private-1a2b3c4d
```

`vcluster_name` has to be the name the platform provisioned the nodes under: the node template
puts it on every instance as a network tag, and the CCM matches nodes and the firewall rules it
creates on that tag.

Set `-var ccm_enabled=false`, `-var ccm_lb_enabled=false` or `-var csi_enabled=false` to leave a
piece out. See [variables.tf](./variables.tf) for the rest.

## Permissions

The node service account is granted the IAM roles the CCM and the CSI driver need by
[the infrastructure stage](../environment/infrastructure/iam.tf), gated on the
`vcluster.com/ccm-enabled` and `vcluster.com/csi-enabled` properties of the NodeProvider or the
NetworkEnvironment. If you leave those at their default of `true` but never apply this module,
the nodes carry permissions nothing uses - set them to `false` on the provider instead.

Those permissions belong to the node, not to the CCM pod, so every pod that can reach the
instance metadata server inherits them. See the security notes in the
[top-level README](../README.md#security-considerations).

## Migrating from 4.12

`suffix` is derived exactly as the in-provider stage derived it, so the object names this module
produces match the ones a 4.12 cluster already has - you get one set of add-ons, not two.

The terraform state does not carry over. The platform kept the old stage's state under a
workspace it no longer reconciles, so the first apply here starts from an empty state against a
cluster that already holds the objects. Do a `terraform plan` first: if the provider reports
conflicts rather than clean no-op creates, `terraform import` the objects, or delete them and let
this module recreate them during a maintenance window.
