terraform {
  cloud {
    organization = "bingnet"   # customize to your tf cloud org name

    workspaces {
      name = "linode-dns-lab"  # unique remote state for this tf plan
    }
  }

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "1.29.4"
    }
  }
}

provider "linode" {
  token = var.token
}

