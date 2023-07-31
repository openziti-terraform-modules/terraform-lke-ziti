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
      version = "~> 2.19"
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

data "terraform_remote_state" "router_state" {
  backend = "local"
  config = {
    path = "${path.root}/../plan-20-ziti-router/terraform.tfstate"
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

resource "helm_release" "rancher" {
  name             = "rancher"
  repository       = "https://releases.rancher.com/server-charts/latest"
  chart            = "rancher"
  version          = "~> 2.7.4"
  timeout          = 600
  namespace        = "cattle-system"
  create_namespace = true
  values = [yamlencode({
    replicas = -1
    hostname = "rancher.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
    ingress = {
      enabled          = true
      ingressClassName = "nginx"
    }
    tls = "external"
    global = {
      cattle = {
        psp = {
          enabled = false # required for k8s >= 1.25
        }
      }
    }
  })]
}

data "restapi_object" "router_identity_lookup" {
  provider     = restapi
  path         = "/identities"
  search_key   = "name"
  search_value = data.terraform_remote_state.router_state.outputs.ziti_router_identity_name
}

resource "restapi_object" "router_identity" {
  depends_on    = [data.restapi_object.router_identity_lookup]
  provider      = restapi
  path          = "/identities"
  update_method = "PATCH"
  data = jsonencode({
    id = jsondecode(data.restapi_object.router_identity_lookup.api_response).data.id
    roleAttributes = concat(
      jsondecode(data.restapi_object.router_identity_lookup.api_response).data.roleAttributes,
      ["rancher-hosts"]
    )
  })
}

# find the id of "edge-client" identity
data "restapi_object" "client_identity_lookup" {
  provider     = restapi
  path         = "/identities"
  search_key   = "name"
  search_value = "edge-client"
}

# append #monitoring-clients to existing client identity's roles
resource "restapi_object" "client_identity" {
  provider      = restapi
  path          = "/identities"
  update_method = "PATCH"
  data = jsonencode({
    id = jsondecode(data.restapi_object.client_identity_lookup.api_response).data.id
    roleAttributes = concat(
      jsondecode(data.restapi_object.client_identity_lookup.api_response).data.roleAttributes,
      ["rancher-clients"]
    )
  })
}

# module "rancher_service" {
#     source = "github.com/openziti-terraform-modules/terraform-openziti-service?ref=v0.1.0"
#     upstream_address         = "rancher.cattle-system.svc"
#     upstream_port            = 443
#     intercept_address        = "rancher.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
#     intercept_port           = 443
#     role_attributes          = ["rancher-services"]
#     name                     = "rancher"
# }

resource "kubernetes_manifest" "rancher_tls" {
  depends_on = [
    helm_release.rancher
  ]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "rancher-tls"
      namespace = "cattle-system"
    }
    spec = {
      commonName = "rancher.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
      dnsNames = [
        "rancher.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
      ]
      duration = "2160h0m0s"
      # ipAddresses = []
      # isCA = false
      issuerRef = {
        group = "cert-manager.io"
        kind  = "ClusterIssuer"
        name  = data.terraform_remote_state.k8s_state.outputs.cluster_issuer_name
      }
      privateKey = {
        algorithm = "RSA"
        encoding  = "PKCS1"
        size      = 2048
      }
      renewBefore = "360h0m0s"
      secretName  = "rancher-tls"
      # secretTemplate = {
      #     annotations = {}
      #     labels = {}
      # }
      subject = {
        organizations = [
          "canary",
        ]
      }
      # uris = [
      #     "spiffe://cluster.local/ns/sandbox/sa/example",
      # ]
      usages = [
        "server auth",
        # "client auth",
      ]
    }
  }
}
