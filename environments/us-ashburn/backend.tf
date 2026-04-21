terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "schmhj"
    workspaces {
      prefix = "oke"
    }
  }
}