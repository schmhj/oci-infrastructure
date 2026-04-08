locals {
  kubeconfig = yamldecode(
    data.terraform_remote_state.oci.outputs.kubeconfig_content
  )
  cluster_endpoint = local.kubeconfig["clusters"][0]["cluster"]["server"]
  cluster_ca_cert  = base64decode(
    local.kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"]
  )

}