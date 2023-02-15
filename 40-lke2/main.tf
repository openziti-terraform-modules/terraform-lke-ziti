terraform {
  cloud {
    organization = "bingnet"  # customize to your tf cloud org name

    workspaces {
      name = "linode-lke2-lab"  # unique remote state workspace for this tf plan
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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.13.0"
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

resource "linode_lke_cluster" "linode_lke" {
    label       = var.label
    k8s_version = var.k8s_version
    region      = var.region
    tags        = var.tags

    dynamic "pool" {
        for_each = var.pools
        content {
            type  = pool.value["type"]
            count = pool.value["count"]
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

provider "kubectl" {     # duplcates config of provider "kubernetes" for cert-manager module
  host                   = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.server
  token                  = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).users[0].user.token
  cluster_ca_certificate = base64decode(yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.certificate-authority-data)
  load_config_file       = false
}

module "cert_manager" {
  source        = "terraform-iaac/cert-manager/kubernetes"

  cluster_issuer_email                   = var.email
  cluster_issuer_name                    = var.cluster_issuer_name
  cluster_issuer_server                  = var.cluster_issuer_server
  cluster_issuer_private_key_secret_name = "${var.cluster_issuer_name}-secret"
  additional_set = [{
    name = "enableCertificateOwnerRef"
    value = "true"
  }]
}

data "template_file" "ingress_nginx_values" {
  template = "${file("values-ingress-nginx.yaml")}"
}

resource "helm_release" "ingress_nginx" {
  depends_on   = [module.cert_manager]
  name       = "ingress-nginx"
  namespace = "ingress-nginx"
  create_namespace = true
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  values = [data.template_file.ingress_nginx_values.rendered]
}

data "template_file" "ziti_router_values" {
  template = "${file("values-ziti-router.yaml")}"
  vars = {
    # cluster-internal endpoint for routers in any namespace
    # ctrl_endpoint = "${helm_release.ziti_controller.name}-ctrl.${var.ziti_controller_namespace}.svc:${var.ctrl_port}"
    # public endpoint for routers outside the cluster
    ctrl_endpoint = "${data.terraform_remote_state.lke_plan.outputs.ctrl_domain_name}.${data.terraform_remote_state.lke_plan.outputs.domain_name}:${data.terraform_remote_state.lke_plan.outputs.ctrl_port}"
  }
}
