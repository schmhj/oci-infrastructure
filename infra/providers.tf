provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}

# Bootstrap kubernetes provider using exec — only needed ONCE in infra stage
# to create the service account. This runs locally or on a TFC Agent.
# provider "kubernetes" {
#   host                   = local.cluster_endpoint
#   cluster_ca_certificate = local.cluster_ca_cert
#   exec {
#     api_version = "client.authentication.k8s.io/v1beta1"
#     command     = "sh"
#     args = [
#       "-c",
#       "$(ls .terraform/providers/registry.terraform.io/oracle/oci/*/*/terraform-provider-oci_*) kube-auth generate-token --cluster-id ${oci_containerengine_cluster.oke.id}"
#     ]
#   }
  # exec {
  #   api_version = "client.authentication.k8s.io/v1beta1"
  #   command     = "oci"
  #   args = [
  #     "ce", "cluster", "generate-token",
  #     "--cluster-id", oci_containerengine_cluster.oke.id,
  #     "--region", var.region
  #   ]
  # }
# }