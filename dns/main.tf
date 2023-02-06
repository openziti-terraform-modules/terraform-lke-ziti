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

resource "linode_domain" "master_domain" {
    type = "master"
    domain = var.domain_name
    soa_email = var.email
    tags = var.tags
}

resource "linode_domain_record" "ingress_domain_name_record" {
    domain_id = linode_domain.master_domain.id
    name = var.ingress_domain_name
    record_type = "A"
    target = var.nodebalancer_ip
}
