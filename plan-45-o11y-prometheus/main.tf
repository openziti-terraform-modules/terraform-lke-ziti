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
    repository_config_path     = "${path.root}/.helm/repositories.yaml" 
    repository_cache           = "${path.root}/.helm"
    kubernetes {
        host                   = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.server
        token                  = yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).users[0].user.token
        cluster_ca_certificate = base64decode(yamldecode(base64decode(data.terraform_remote_state.k8s_state.outputs.kubeconfig)).clusters[0].cluster.certificate-authority-data)
    }
}

locals {
}

# resource "terraform_data" "helm_update" {
#     count = 0 # set to 1 to trigger helm repo update
#     triggers_replace = [
#         timestamp()
#     ]
#     provisioner "local-exec" {
#         command = "helm repo update openziti"
#     }
# }

# resource "random_password" "grafana_password" {
#     length           = 16
#     special          = true
#     override_special = "!#$%&*()-_=+[]{}<>:?"
# }

# resource "kubernetes_secret" "grafana_password" {
#     depends_on = [
#         kubernetes_namespace.monitoring
#     ]
#     metadata {
#         name      = "grafana-password"
#         namespace = "monitoring"
#     }
#     data = {
#         admin-password = random_password.grafana_password.result
#     }
# }

resource "kubernetes_namespace" "monitoring" {
    metadata {
        name = "monitoring"
        labels = {
            # this label is selected by trust-manager to sync the CA trust bundle
            "openziti.io/namespace": "enabled"
        }
    }
}

resource "helm_release" "prometheus" {
    depends_on = [
        kubernetes_namespace.monitoring
    ]
    chart         = "kube-prometheus-stack"
    repository    = "https://prometheus-community.github.io/helm-charts"
    name          = "prometheus-stack"
    namespace     = "monitoring"
    # wait       = false  # hooks don't run if wait=true!?
    # let the chart generate the grafana password and save it in namespace monitoring/{{ include "grafana.fullname" . }}
    # set {
    #     # set the admin password for the Grafana UI
    #     name  = "grafana.adminPassword"
    #     value = random_password.grafana_password.result
    # }
    # these allow Prometheus to discover the ServiceMonitors and PodMonitors in other namespaces
    set {
        name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
        value = "false"
    }
    set {
        name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
        value = "false"
    }
    values = [yamlencode({
        grafana = {
            sidecar = {
                dashboards = {
                    # this pairs with the default value of
                    # sidecar.dashboards.label to select configmaps that define
                    # dashboards
                    labelValue = "true"
                }
            }
        }
    })]
}

resource "kubernetes_config_map" "nginx_overview_dashboard" {
    metadata {
        name      = "nginx-overview-dashboard"
        namespace = "monitoring"
        labels = {
            "grafana_dashboard" = "true"
        }
    }
    data = {
        "nginx-overview.json" = file("${path.root}/dashboards/nginx-overview.json")
    }
}

resource "kubernetes_config_map" "nginx_requests_dashboard" {
    metadata {
        name      = "nginx-requests-dashboard"
        namespace = "monitoring"
        labels = {
            "grafana_dashboard" = "true"
        }
    }
    data = {
        "nginx-requests.json" = file("${path.root}/dashboards/nginx-requests.json")
    }
}

resource "kubernetes_config_map" "openziti_dashboard" {
    metadata {
        name      = "openziti-dashboard"
        namespace = "monitoring"
        labels = {
            "grafana_dashboard" = "true"
        }
    }
    data = {
        "openziti.json" = file("${path.root}/dashboards/openziti.json")
    }
}

