terraform {
  cloud {
    organization = "bingnet"  # customize to your tf cloud org name

    workspaces {
      name = "linode-dns2-lab"  # unique remote state workspace for this tf plan
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

resource "linode_domain" "cluster_zone" {
    type = "master"
    domain = var.domain_name
    soa_email = var.email
    tags = var.tags
}

resource "linode_domain_record" "wildcard_record" {
    domain_id = linode_domain.cluster_zone.id
    name = "*"
    record_type = "A"
    target = var.nodebalancer_ip
    ttl_sec = var.wildcard_ttl_sec
}
