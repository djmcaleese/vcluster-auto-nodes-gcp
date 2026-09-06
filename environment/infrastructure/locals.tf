locals {
  project            = module.validation.project
  region             = module.validation.region
  project_region_key = format("%s-%s", local.project, local.region)

  # Network environments are cluster scoped and shared between tenant clusters, so there is
  # no vCluster instance to name them after. var.vcluster.name is the NetworkEnvironment name
  # and var.vcluster.namespace is the namespace the platform itself runs in.
  environment_name      = nonsensitive(var.vcluster.name)
  environment_namespace = nonsensitive(var.vcluster.namespace)

  # A random_id resource cannot be used here because of how the VPC module applies resources.
  # The module needs resource names to be known in advance.
  random_id = substr(md5(format("%s%s", local.environment_namespace, local.environment_name)), 0, 8)

  public_subnet_name  = format("public-%s", local.random_id)
  private_subnet_name = format("private-%s", local.random_id)

  # var.vcluster.properties is the merge of the NodeProvider's and the NetworkEnvironment's
  # properties, and nothing else. Properties set per tenant cluster under
  # privateNodes.autoNodes[*].properties reach the node template only, so everything below has to
  # be set on the NodeProvider or on the NetworkEnvironment to take effect.
  vpc_cidr   = nonsensitive(try(var.vcluster.properties["vcluster.com/vpc-cidr"], "10.10.0.0/16"))
  vpc_prefix = nonsensitive(tonumber(element(split("/", local.vpc_cidr), 1)))
  subnet_prefix = nonsensitive(
    tonumber(
      try(
        var.vcluster.properties["vcluster.com/subnet-prefix"],
        # the original, inconsistently underscored spelling of the same property
        var.vcluster.properties["vcluster.com/subnet_prefix"],
        "24"
      )
    )
  )
  public_subnet_cidr  = cidrsubnet(local.vpc_cidr, local.subnet_prefix - local.vpc_prefix, 0)
  private_subnet_cidr = cidrsubnet(local.vpc_cidr, local.subnet_prefix - local.vpc_prefix, 1)

  # These gate the IAM grants on the node service account only. Deploying the CCM and the CSI
  # driver themselves is no longer something a node provider can do - see ../../addons.
  ccm_enabled = nonsensitive(try(tobool(var.vcluster.properties["vcluster.com/ccm-enabled"]), true))
  csi_enabled = nonsensitive(try(tobool(var.vcluster.properties["vcluster.com/csi-enabled"]), true))
}
