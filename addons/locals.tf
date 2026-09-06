locals {
  # Kept byte-identical to the derivation the removed in-provider kubernetes stage used, so a
  # tenant cluster that already had these add-ons applied by the platform on 4.12 adopts the
  # objects it already has instead of ending up with a second copy under different names.
  suffix = substr(md5(format("%s%s", var.node_provider_name, var.vcluster_name)), 0, 8)
}
