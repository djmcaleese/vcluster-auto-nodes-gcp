variable "kubeconfig" {
  description = "Path to a kubeconfig for the tenant cluster these add-ons are deployed into."
  type        = string
}

variable "kubeconfig_context" {
  description = "Context to select within kubeconfig. Defaults to its current context."
  type        = string
  default     = ""
}

variable "vcluster_name" {
  description = <<-EOT
    Name of the tenant cluster. The node template puts this on every instance as the `vcluster`
    label and as a network tag, and the CCM matches nodes and the firewall rules it creates on
    that tag, so this has to be the name the platform provisioned the nodes under.
  EOT
  type        = string
}

variable "node_provider_name" {
  description = <<-EOT
    Name of the NodeProvider that provisioned the nodes. The CCM only schedules onto nodes
    labelled with it, so a tenant cluster drawing nodes from several providers needs one instance
    of this module per provider.
  EOT
  type        = string
}

variable "network_name" {
  description = "The network_name output of the NetworkEnvironment's infrastructure stage."
  type        = string
}

variable "subnet_name" {
  description = "The subnet_name output of the NetworkEnvironment's infrastructure stage."
  type        = string
}

variable "ccm_enabled" {
  description = "Deploy the GCP Cloud Controller Manager."
  type        = bool
  default     = true
}

variable "ccm_lb_enabled" {
  description = "Run the CCM's service controller, which reconciles LoadBalancer services into GCP load balancers. When false the CCM still initializes nodes but creates no load balancers."
  type        = bool
  default     = true
}

variable "csi_enabled" {
  description = "Deploy the GCP Persistent Disk CSI driver and a `<provider>-default-disk` storage class."
  type        = bool
  default     = true
}
