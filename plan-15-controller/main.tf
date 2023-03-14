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

data "terraform_remote_state" "lke_state" {
    backend = "local"
    config = {
        path = "${path.root}/../plan-10-k8s/terraform.tfstate"
    }
}

provider "helm" {
    repository_config_path = "${path.root}/.helm/repositories.yaml" 
    repository_cache       = "${path.root}/.helm"
    kubernetes {
        host                   = yamldecode(base64decode(data.terraform_remote_state.lke_state.outputs.kubeconfig)).clusters[0].cluster.server
        token                  = yamldecode(base64decode(data.terraform_remote_state.lke_state.outputs.kubeconfig)).users[0].user.token
        cluster_ca_certificate = base64decode(yamldecode(base64decode(data.terraform_remote_state.lke_state.outputs.kubeconfig)).clusters[0].cluster.certificate-authority-data)
    }
}

provider "kubernetes" {
        host                   = yamldecode(base64decode(data.terraform_remote_state.lke_state.outputs.kubeconfig)).clusters[0].cluster.server
        token                  = yamldecode(base64decode(data.terraform_remote_state.lke_state.outputs.kubeconfig)).users[0].user.token
        cluster_ca_certificate = base64decode(yamldecode(base64decode(data.terraform_remote_state.lke_state.outputs.kubeconfig)).clusters[0].cluster.certificate-authority-data)
}

provider "kubectl" {     # duplcates config of provider "kubernetes" for cert-manager module
        host                   = yamldecode(base64decode(data.terraform_remote_state.lke_state.outputs.kubeconfig)).clusters[0].cluster.server
        token                  = yamldecode(base64decode(data.terraform_remote_state.lke_state.outputs.kubeconfig)).users[0].user.token
        cluster_ca_certificate = base64decode(yamldecode(base64decode(data.terraform_remote_state.lke_state.outputs.kubeconfig)).clusters[0].cluster.certificate-authority-data)
}

module "ziti_controller" {
    source = "../modules/ziti-controller-nginx"
    ziti_charts = var.ziti_charts
    ziti_controller_release = var.ziti_controller_release
    ziti_namespace = data.terraform_remote_state.lke_state.outputs.ziti_namespace
    dns_zone = data.terraform_remote_state.lke_state.outputs.dns_zone
}

resource "helm_release" "ziti_console" {
    name             = var.ziti_console_release
    namespace        = data.terraform_remote_state.lke_state.outputs.ziti_namespace
    repository       = "https://openziti.github.io/helm-charts"
    chart            = var.ziti_charts != "" ? "${var.ziti_charts}/ziti-console" : "ziti-console"
    version          = "<0.3"
    values           = [yamlencode({
        ingress = {
            enabled = "true"
            ingressClassName = "nginx"
            annotations = {
                "cert-manager.io/cluster-issuer" = data.terraform_remote_state.lke_state.outputs.cluster_issuer_name
            }
            advertisedHost = "console.${data.terraform_remote_state.lke_state.outputs.dns_zone}"
            tlsSecret = "${var.ziti_console_release}-tls-secret"
        }
        settings = {
            edgeControllers = [{
                name = "Ziti Edge Mgmt API"
                url = "https://${var.ziti_controller_release}-mgmt.${data.terraform_remote_state.lke_state.outputs.ziti_namespace}.svc:443"
                default = "true"
            }]
        }
    })]
}
