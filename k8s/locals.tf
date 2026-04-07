locals {
  kubeconfig = yamldecode(
    data.terraform_remote_state.infra.outputs.kubeconfig_content
  )
  cluster_endpoint = local.kubeconfig["clusters"][0]["cluster"]["server"]
  cluster_ca_cert  = base64decode(
    local.kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"]
  )

  cluster_token = local.kubeconfig["users"][0]["user"]["token"]
}