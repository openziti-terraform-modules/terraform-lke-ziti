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
            source = "qrkourier/restapi"
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

provider restapi {
    uri                   = "https://${data.terraform_remote_state.controller_state.outputs.ziti_controller_mgmt_external_host}:443/edge/management/v1"
    cacerts_string        = (data.terraform_remote_state.controller_state.outputs.ctrl_plane_cas).data["ctrl-plane-cas.crt"]
    ziti_username         = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-user"]
    ziti_password         = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-password"]
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

data "restapi_object" "router_identity_lookup" {
    provider     = restapi
    path         = "/identities"
    search_key   = "name"
    search_value = data.terraform_remote_state.router_state.outputs.ziti_router_identity_name
}

resource "restapi_object" "router_identity" {
    depends_on         = [data.restapi_object.router_identity_lookup]
    provider           = restapi
    path               = "/identities"
    update_method      = "PATCH"
    data               = jsonencode({
        id             = jsondecode(data.restapi_object.router_identity_lookup.api_response).data.id
        roleAttributes = concat(
            jsondecode(data.restapi_object.router_identity_lookup.api_response).data.roleAttributes, 
            ["monitoring-hosts"]
        )
    })
}

resource "kubernetes_manifest" "ziti_service_monitor" {
    manifest = {
        apiVersion = "monitoring.coreos.com/v1"
        kind = "ServiceMonitor"
        metadata = {
            labels = {
                team = "ziggy-ops"
                release = "prometheus-stack"
            }
            name = "ziti-monitor"
            namespace = "monitoring"
        }
        spec = {
            endpoints = [
                {
                    port = "prometheus"
                    interval = "30s"
                    scheme = "https"
                    tlsConfig = {
                        # the trust bundle is available in namespace, but I
                        # don't know how to express in the Prometheus resource,
                        # or wherever, that it it contains trusted issuer certs
                        # for scrape targets
                        insecureSkipVerify = true  
                    }
                },
            ]
            namespaceSelector = {
                matchNames = [
                    "ziti"
                ]
            }
            selector = {
                matchLabels = {
                    "prometheus.openziti.io/scrape" = "true"
                }
            }
        }
    }
}

module "prometheus_service" {
    source                   = "../modules/simple-tunneled-service"
    upstream_address         = "prometheus-operated.monitoring.svc"
    upstream_port            = 9090
    intercept_address        = "prometheus.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
    intercept_port           = 80
    role_attributes          = ["monitoring-services"]
    bind_identity_roles      = ["#monitoring-hosts"]
    dial_identity_roles      = ["#monitoring-clients"]
    name                     = "prometheus"
}

module "grafana_service" {
    source                   = "../modules/simple-tunneled-service"
    upstream_address         = "prometheus-stack-grafana.monitoring.svc"
    upstream_port            = 80
    intercept_address        = "grafana.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
    intercept_port           = 80
    role_attributes          = ["monitoring-services"]
    bind_identity_roles      = ["#monitoring-hosts"]
    dial_identity_roles      = ["#monitoring-clients"]
    name                     = "grafana"
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
    provider           = restapi
    path               = "/identities"
    update_method      = "PATCH"
    data               = jsonencode({
        id             = jsondecode(data.restapi_object.client_identity_lookup.api_response).data.id
        roleAttributes = concat(
            jsondecode(data.restapi_object.client_identity_lookup.api_response).data.roleAttributes,
            ["monitoring-clients"]
        )
    })
}
