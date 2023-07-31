terraform {
  cloud {}
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.45"
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
      version = "~> 2.19"
    }
  }
}

provider "tfe" {
  # token    = var.tf_token
}

data "tfe_outputs" "k8s_state" {
  organization = var.tf_cloud_remote_state_organization
  workspace    = var.tf_cloud_remote_state_k8s_workspace
}

provider "helm" {
  repository_config_path = "${path.root}/.helm/repositories.yaml"
  repository_cache       = "${path.root}/.helm"
  kubernetes {
    host                   = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.server
    token                  = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).users[0].user.token
    cluster_ca_certificate = base64decode(yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.certificate-authority-data)
  }
}

provider "kubernetes" {
  host                   = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.server
  token                  = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).users[0].user.token
  cluster_ca_certificate = base64decode(yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.certificate-authority-data)
}

provider "kubectl" { # duplcates config of provider "kubernetes" for cert-manager module
  host                   = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.server
  token                  = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).users[0].user.token
  cluster_ca_certificate = base64decode(yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.certificate-authority-data)
}

module "ziti_controller" {
  source                  = "github.com/openziti-test-kitchen/terraform-k8s-ziti-controller?ref=v0.1.1"
  ziti_charts             = var.ziti_charts
  ziti_controller_release = var.ziti_controller_release
  ziti_namespace          = data.terraform_remote_state.k8s_state.outputs.ziti_namespace
  dns_zone                = data.terraform_remote_state.k8s_state.outputs.dns_zone
  storage_class           = var.storage_class
  values = {
    image = {
      repository = var.container_image_repository
      tag        = var.container_image_tag != "" ? var.container_image_tag : ""
      pullPolicy = var.container_image_pull_policy
    }
    prometheus = {
      service = {
        enabled = true
        labels = {
          # matched by the label selector on prometheus operator ServiceMonitor resource
          "prometheus.openziti.io/scrape" = "true"
        }
      }
    }
    fabric = {
      events = {
        enabled = true
      }
    }
  }
}

resource "helm_release" "ziti_console" {
  name       = var.ziti_console_release
  namespace  = data.terraform_remote_state.k8s_state.outputs.ziti_namespace
  repository = "https://openziti.github.io/helm-charts"
  chart      = var.ziti_charts != "" ? "${var.ziti_charts}/ziti-console" : "ziti-console"
  version    = "~> 0.3"
  values = [yamlencode({
    ingress = {
      enabled          = "true"
      ingressClassName = "nginx"
      annotations = {
        "cert-manager.io/cluster-issuer" = data.terraform_remote_state.k8s_state.outputs.cluster_issuer_name
      }
      advertisedHost = "console.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
      tlsSecret      = "${var.ziti_console_release}-tls-secret"
    }
    settings = {
      edgeControllers = [{
        name    = "Ziti Edge Mgmt API"
        url     = "https://${var.ziti_controller_release}-mgmt.${data.terraform_remote_state.k8s_state.outputs.ziti_namespace}.svc:443"
        default = "true"
      }]
    }
  })]
}
