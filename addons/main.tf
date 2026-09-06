provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
}

##########
# CCM
#########

module "kubernetes_apply_ccm" {
  source = "./apply"

  for_each = var.ccm_enabled ? { "enabled" = true } : {}

  manifest_file = "${path.module}/manifests/ccm.yaml.tftpl"
  template_vars = {
    suffix             = local.suffix
    network_name       = var.network_name
    subnet_name        = var.subnet_name
    vcluster_name      = var.vcluster_name
    node_provider_name = var.node_provider_name
    controllers        = var.ccm_lb_enabled ? "*,-node-ipam-controller" : "*,-service,-node-ipam-controller"
  }
}

##########
# CSI
##########

module "kubernetes_apply_csi" {
  source = "./apply"

  for_each = var.csi_enabled ? { "enabled" = true } : {}

  # The oldest supported k8s version is 1.30.x, that requires CSI Driver 1.13.x
  manifest_file   = "${path.module}/manifests/csi.yaml.tftpl"
  computed_fields = ["globalDefault"]

  template_vars = {
    suffix             = local.suffix
    node_provider_name = var.node_provider_name
  }
}
