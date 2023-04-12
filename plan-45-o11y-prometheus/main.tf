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

resource "terraform_data" "helm_update" {
    count = 0 # set to 1 to trigger helm repo update
    triggers_replace = [
        timestamp()
    ]
    provisioner "local-exec" {
        command = "helm repo update openziti"
    }
}

resource "random_password" "grafana_password" {
    length           = 16
    special          = true
    override_special = "!#$%&*()-_=+[]{}<>:?"
}

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
    set {
        # set the admin password for the Grafana UI
        name  = "grafana.adminPassword"
        value = random_password.grafana_password.result
    }
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
            dashboards = {
                default = {
                    nginx-overview = {
                        url = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/grafana/dashboards/nginx.json"
                    }
                    nginx-requests = {
                        url = "https://github.com/kubernetes/ingress-nginx/raw/main/deploy/grafana/dashboards/request-handling-performance.json"
                    }
                }
            }
        }
    })]
}
