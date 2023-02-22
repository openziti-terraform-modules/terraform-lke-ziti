terraform {
  # Configure Terraform Cloud with env vars:
  #   TF_CLOUD_ORGANIZATION
  #   TF_WORKSPACE
  cloud {}

  required_providers {
     local = {
      version = "~> 2.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.0.1"
    }
  }
}

data "terraform_remote_state" "lke_plan" {
  backend = "remote"

  config = {
    organization = var.tf_org
    workspaces = {
      name = var.tf_workspace_zitik8s
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.server
    token                  = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).users[0].user.token
    cluster_ca_certificate = base64decode(yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.certificate-authority-data)
  }
}

provider "kubernetes" {
  host                   = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.server
  token                  = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).users[0].user.token
  cluster_ca_certificate = base64decode(yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.certificate-authority-data)
}

resource "helm_release" "ziti_router" {
  depends_on = [helm_release.trust_manager, helm_release.ingress_nginx]
  namespace = var.ziti_router_namespace
  create_namespace = true
  name = "ziti-router"
  chart = "./charts/ziti-router"
  values = [data.template_file.ziti_router_values.rendered]
}
