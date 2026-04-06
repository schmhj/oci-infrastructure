terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "schmhj"
    workspaces {
      name = "cloud-workspace-oci"
    }
  }
}
