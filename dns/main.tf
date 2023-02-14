terraform {
  cloud {
    organization = "bingnet"  # customize to your tf cloud org name

    workspaces {
      name = "linode-dns-lab"  # unique remote state workspace for this tf plan
    }
  }

required_providers {
     local = {
      version = "~> 2.1"
    }
    linode = {
      source  = "linode/linode"
      version = "1.29.4"
    }
  }
}

provider "linode" {
  token = var.token
}

data "terraform_remote_state" "lke_plan" {
  backend = "remote"

  config = {
    organization = "bingnet"
    workspaces = {
      name = "linode-lke-lab"
    }
  }
}

resource "linode_domain" "cluster_zone" {
    type = "master"
    domain = data.terraform_remote_state.lke_plan.outputs.domain_name
    soa_email = data.terraform_remote_state.lke_plan.outputs.email
    tags = data.terraform_remote_state.lke_plan.outputs.tags
}

resource "linode_domain_record" "wildcard_record" {
    domain_id = linode_domain.cluster_zone.id
    name = "*"
    record_type = "A"
    target = var.nodebalancer_ip
}
