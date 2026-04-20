terraform {
  required_version = ">= 1.7"

  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "schmhj"
    
    workspaces {
      name = "oke-us-ashburn"
    }
  }

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.45"
    }
  }
}

provider "oci" {
  # Credentials come from environment variables set by the OIDC action:
  # OCI_TENANCY_OCID, OCI_USER_OCID, OCI_FINGERPRINT, OCI_PRIVATE_KEY_PATH, OCI_REGION
  # No hardcoded values here — the provider reads them automatically.
}
