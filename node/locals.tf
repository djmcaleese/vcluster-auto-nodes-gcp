locals {
  project = module.validation.project
  region  = module.validation.region
  zone    = module.validation.zone

  # var.vcluster.name/namespace fall back to the node claim when a node is claimed outside of a
  # tenant cluster, so they are safer than reaching into var.vcluster.instance, which is null then.
  vcluster_name      = nonsensitive(var.vcluster.name)
  vcluster_namespace = nonsensitive(var.vcluster.namespace)

  network_name          = nonsensitive(var.vcluster.networkEnvironment.outputs.infrastructure["network_name"])
  subnet_name           = nonsensitive(var.vcluster.networkEnvironment.outputs.infrastructure["subnet_name"])
  service_account_email = nonsensitive(var.vcluster.networkEnvironment.outputs.infrastructure["service_account_email"])

  instance_type = nonsensitive(var.vcluster.nodeType.spec.properties["instance-type"])

  # GPU families can't live-migrate, so they must TERMINATE on host maintenance.
  # Standard families reject TERMINATE (unless Spot), so they must MIGRATE.
  machine_family       = split("-", local.instance_type)[0]
  gpu_machine_families = ["a2", "a3", "a4", "g2"]
  on_host_maintenance  = contains(local.gpu_machine_families, local.machine_family) ? "TERMINATE" : "MIGRATE"
}
