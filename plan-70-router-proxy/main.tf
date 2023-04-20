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

module "ziti_router_proxy1" {
    # source                    = "/home/kbingham/Sites/netfoundry/github/terraform-k8s-openziti-router"
    source                    = "github.com/openziti-test-kitchen/terraform-k8s-ziti-router?ref=v0.1.2"
    name                      = "proxy1"
    image_repo                = var.container_image_repo
    image_tag                 = var.container_image_tag
    image_pull_policy         = var.container_image_pull_policy
    namespace                 = data.terraform_remote_state.k8s_state.outputs.ziti_namespace
    ctrl_endpoint             = "${data.terraform_remote_state.controller_state.outputs.ziti_controller_ctrl_internal_host}:443"
    ziti_charts               = var.ziti_charts
    storage_class             = var.storage_class
    router_properties         = {
        isTunnelerEnabled = true
        roleAttributes = [
            "proxy-routers"
        ]
    }
    values = {
        fabric = {
            metrics = {
                enabled = true
            }
        }
        tunnel = {
            mode = "proxy"
            proxyServices = [
                {
                    zitiService = "testapi-service"
                    containerPort = 8080
                    advertisedPort = 80
                }
            ]
            proxyDefaultK8sService = {
                enabled = true
                type = "ClusterIP"
            }
        }
    }
}

data "restapi_object" "testapi_service_lookup" {
    provider     = restapi
    path         = "/services"
    search_key   = "name"
    search_value = "testapi-service"
}

resource "restapi_object" "testapi_service" {
    depends_on         = [data.restapi_object.testapi_service_lookup]
    provider           = restapi
    path               = "/services"
    update_method      = "PATCH"
    data               = jsonencode({
        id             = jsondecode(data.restapi_object.testapi_service_lookup.api_response).data.id
        roleAttributes = concat(
            jsondecode(data.restapi_object.testapi_service_lookup.api_response).data.roleAttributes, 
            ["proxy-services"]
        )
    })
}

data "restapi_object" "proxy1_identity_lookup" {
    provider     = restapi
    path         = "/identities"
    search_key   = "name"
    search_value = "proxy1"
}

resource "restapi_object" "proxy1_identity" {
    depends_on         = [data.restapi_object.proxy1_identity_lookup]
    provider           = restapi
    path               = "/identities"
    update_method      = "PATCH"
    data               = jsonencode({
        id             = jsondecode(data.restapi_object.proxy1_identity_lookup.api_response).data.id
        roleAttributes = [
            "testapi-clients"
        ]
    })
}

resource "restapi_object" "testapi_service_router_policy" {
    provider           = restapi
    path               = "/service-edge-router-policies"
    data               = jsonencode({
        name = "proxy-service-router-policy"
        semantic = "AnyOf"
        edgeRouterRoles = [
            "#proxy-routers"
        ]
        serviceRoles = [
            "#proxy-services"
        ]
    })
}

resource "kubernetes_manifest" "testapi_ingress" {
    manifest = {
        apiVersion = "networking.k8s.io/v1"
        kind = "Ingress"
        metadata = {
            annotations = {
                "cert-manager.io/cluster-issuer" = data.terraform_remote_state.k8s_state.outputs.cluster_issuer_name
            }
            name = "testapi"
            namespace = "ziti"
        }
        spec = {
            ingressClassName = "nginx"
            rules = [
                {
                    host = "testapi.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
                    http = {
                        paths = [
                            {
                                backend = {
                                    service = {
                                        name = "proxy1-router-proxy-default"
                                        port = {
                                            name = "testapi-service"
                                        }
                                    }
                                }
                                path = "/"
                                pathType = "Prefix"
                            },
                        ]
                    }
                },
            ]
            tls = [
                {
                    hosts = [
                        "testapi.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
                    ]
                    secretName = "testapi-tls-secret"
                },
            ]
        }
    }
}
