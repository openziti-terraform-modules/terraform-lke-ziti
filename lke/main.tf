terraform {
  cloud {
    organization = "bingnet"  # customize to your tf cloud org name

    workspaces {
      name = "linode-lke-lab"  # unique remote state workspace for this tf plan
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

resource "kubernetes_namespace" ziti_controller {
  metadata {
    name = var.ziti_controller_namespace
  }
}

resource "helm_release" "trust_manager" {
  depends_on   = [module.cert_manager, kubernetes_namespace.ziti_controller]
  chart      = "trust-manager"
  repository = "https://charts.jetstack.io"
  name       = "trust-manager-release"
  namespace  = module.cert_manager.namespace
  set {
    name = "app.trust.namespace"
    value = var.ziti_controller_namespace
  }
}

data "template_file" "ingress_nginx_values" {
  template = "${file("values-ingress-nginx.yaml")}"
  vars = {
    # nodebalancer_id = linode_nodebalancer.ingress_nginx_nodebalancer.id
    client_port = var.ziti_client_port
    client_svc = var.ziti_client_svc
    controller_namespace = var.ziti_controller_namespace
  }
}

resource "helm_release" "ingress-nginx" {
  depends_on   = [module.cert_manager]
  name       = "ingress-nginx-release"
  namespace = "ingress-nginx"
  create_namespace = true
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  values = [data.template_file.ingress_nginx_values.rendered]
}

data "template_file" "ziti_controller_values" {
  template = "${file("values-ziti-controller.yaml")}"
  vars = {
    ctrl_port = var.ziti_ctrl_port
    client_port = var.ziti_client_port
    mgmt_port = var.ziti_mgmt_port
    ziti_domain_name = var.ziti_domain_name
    domain_name = var.domain_name
  }
}

resource "helm_release" "ziti_controller" {
  depends_on = [helm_release.trust_manager]
  namespace = var.ziti_controller_namespace
  create_namespace = true
  name = "ziti-controller-release"
  chart = "./charts/ziti-controller"
  values = [data.template_file.ziti_controller_values.rendered]
}

data "template_file" "ziti_console_values" {
  template = "${file("values-ziti-console.yaml")}"
  vars = {
    cluster_issuer = var.cluster_issuer_name
    domain_name = var.domain_name
    ziti_domain_name = var.ziti_domain_name
    controller_namespace = helm_release.ziti_controller.namespace
    controller_release = helm_release.ziti_controller.name
    console_release = var.ziti_console_release
    edge_mgmt_port = var.ziti_mgmt_port
  }
}

resource "helm_release" "ziti_console" {
  depends_on = [helm_release.ingress-nginx]
  name = var.ziti_console_release
  namespace = "ziti-console"
  create_namespace = true
  chart = "./charts/ziti-console"
  values = [data.template_file.ziti_console_values.rendered]
}
