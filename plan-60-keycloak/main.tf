terraform {
  backend "local" {}
  # If you want to save state in Terraform Cloud:
  # Configure these env vars, uncomment cloud {} 
  # and comment out backend "local" {}
  #   TF_CLOUD_ORGANIZATION
  #   TF_WORKSPACE
  # cloud {}
  required_providers {
    local = {
      version = "~> 2.1"
    }
    restapi = {
      source  = "qrkourier/restapi"
      version = "~> 1.23.0"
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

data "terraform_remote_state" "k8s_state" {
  backend = "local"
  config = {
    path = "${path.root}/../plan-10-k8s/terraform.tfstate"
  }
}

data "terraform_remote_state" "controller_state" {
  backend = "local"
  config = {
    path = "${path.root}/../plan-15-ziti-controller/terraform.tfstate"
  }
}

provider "restapi" {
  uri            = "https://${data.terraform_remote_state.controller_state.outputs.ziti_controller_mgmt_external_host}:443/edge/management/v1"
  cacerts_string = (data.terraform_remote_state.controller_state.outputs.ctrl_plane_cas).data["ctrl-plane-cas.crt"]
  ziti_username  = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-user"]
  ziti_password  = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-password"]
}

provider "kubernetes" {
  host                   = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.server
  token                  = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).users[0].user.token
  cluster_ca_certificate = base64decode(yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.certificate-authority-data)
}

provider "kubectl" {
  host                   = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.server
  token                  = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).users[0].user.token
  cluster_ca_certificate = base64decode(yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.certificate-authority-data)
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

locals {
}

resource "helm_release" "keycloak" {
  name       = "keycloak"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "keycloak"
  # version    = "15.0.0"
  namespace = "keycloak"
  values = [yamlencode({
    service = {
      type = "ClusterIP"
    }
    ingress = {
      enabled          = true
      ingressClassName = "nginx"
      hostname         = "keycloak.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
      annotations = {
        "cert-manager.io/cluster-issuer" = data.terraform_remote_state.k8s_state.outputs.cluster_issuer_name
      }
      tls = true
    }
    global = {
      storageClass = var.storage_class
    }
  })]
}

