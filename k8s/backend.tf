terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "schmhj"
    workspaces {
      name = "cloud-workspace-k8s"
    }
  }
}

data "terraform_remote_state" "infra" {
  backend = "remote"
  config = {
    organization = "schmhj"
    workspaces = {
      name = "cloud-workspace-oci"        # Stage 1 workspace name
    }
  }
}
