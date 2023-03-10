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
            version = "2.0.1"
        }
        restapi = {
            source = "qrkourier/restapi"
            version = "~> 1.21.0"
        }
    }
}

data "terraform_remote_state" "lke_state" {
    backend = "local"
    config = {
        path = "${path.root}/../plan-10-lke/terraform.tfstate"
    }
}

provider restapi {
    uri                   = "https://${data.terraform_remote_state.lke_state.outputs.ziti_controller_external_host}:${data.terraform_remote_state.lke_state.outputs.mgmt_port}/edge/management/v1"
    debug                 = true
    cacerts_file          = "${path.root}/../plan-10-lke/.terraform/tmp/ctrl-plane-cas.crt"
    ziti_username         = "${data.terraform_remote_state.lke_state.outputs.ziti_admin_user}"
    ziti_password         = "${data.terraform_remote_state.lke_state.outputs.ziti_admin_password}"
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
    load_config_file       = false
}

# from this point onward we have everything we need to use the Ziti mgmt API:
# DNS, CA certs, and username/password. Subsequent Ziti restapi_object resources
# should depend on this or any following restapi_object to ensure these
# prerequesites are satisfied.
resource "restapi_object" "router1" {
    debug       = true
    provider    = restapi
    path        = "/edge-routers"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "router1",
            "isTunnelerEnabled": true,
            "roleAttributes": [
                "public-routers",
                "mgmt-servers"
            ]
        }
    EOF
}

# data "restapi_object" "router1" {
#     depends_on = [restapi_object.router1]
#     provider    = restapi
#     path = "/edge-routers"
#     search_key = "name"
#     search_value = "router1"
#     results_key = "data"
# }

data "template_file" "ziti_router1_values" {
    template = "${file("helm-chart-values/values-ziti-router1.yaml")}"
    vars = {
        ctrl_endpoint = "${data.terraform_remote_state.lke_state.outputs.ziti_controller_ctrl}"
        # ctrl_endpoint = "${var.ctrl_domain_name}.${var.domain_name}:${var.ctrl_port}"
        router1_edge = "${var.router1_edge_domain_name}.${coalesce(var.domain_name, data.terraform_remote_state.lke_state.outputs.domain_name)}"
        router1_transport = "${var.router1_transport_domain_name}.${coalesce(var.domain_name, data.terraform_remote_state.lke_state.outputs.domain_name)}"
        jwt = "${ try(jsondecode(restapi_object.router1.api_response).data.enrollmentJwt, "dummystring") }"
    }
}

resource "helm_release" "ziti_router1" {
    depends_on = [restapi_object.router1]
    name = var.router1_release
    namespace = "${data.terraform_remote_state.lke_state.outputs.ziti_namespace}"
    repository = "https://openziti.github.io/helm-charts"
    chart = "ziti-router"
    version = "<0.3"
    wait = false
    values = [data.template_file.ziti_router1_values.rendered]
}

resource "restapi_object" "router1_identity" {
    debug   = true
    provider    = restapi
    path        = "/identities"
    read_search = {
        results_key = "data"
    }
    update_method = "patch"
    data = <<-EOF
        {
            "id": "aRdvIIfCA7",
            "roleAttributes": [
                "mgmt-servers6"
            ]
        }
    EOF
}

resource "restapi_object" "client_identity" {
    provider    = restapi
    path        = "/identities"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "edge-client",
            "type": "Device",
            "isAdmin": false,
            "enrollment": {
                "ott": true
            },
            "roleAttributes": [
                "webhook-clients",
                "k8sapi-clients",
                "mgmt-clients"
            ]
        }
    EOF
}

resource "local_file" "client_identity" {
    depends_on = [restapi_object.client_identity]
    content  = try(jsondecode(restapi_object.client_identity.api_response).data.enrollment.ott.jwt, "dummystring")
    # filename = "${path.root}/.terraform/tmp/edge-client.jwt"
    filename = "/tmp/lke-edge-client.jwt"
}

resource "restapi_object" "mgmt_intercept_config" {
    depends_on = [data.restapi_object.intercept_v1_config_type]
    provider    = restapi
    path        = "/configs"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "mgmt-intercept-config",
            "configTypeId": "${jsondecode(data.restapi_object.intercept_v1_config_type.api_response).data.id}",
            "data": {
                "protocols": ["tcp"],
                "addresses": ["mgmt.ziti"], 
                "portRanges": [{"low":443, "high":443}]
            }
        }
    EOF
}

resource "restapi_object" "mgmt_host_config" {
    provider    = restapi
    path        = "/configs"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "mgmt-host-config",
            "configTypeId": "${jsondecode(data.restapi_object.host_v1_config_type.api_response).data.id}",
            "data": {
                "protocol": "tcp",
                "address": "${data.terraform_remote_state.lke_state.outputs.ziti_controller_mgmt_internal_host}",
                "port": ${data.terraform_remote_state.lke_state.outputs.mgmt_port}
            }
        }
    EOF
}

resource "restapi_object" "mgmt_service" {
    depends_on = [
        restapi_object.mgmt_intercept_config,
        restapi_object.mgmt_host_config
    ]
    provider    = restapi
    path        = "/services"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "mgmt-service",
            "encryptionRequired": true,
            "configs": [
                "${jsondecode(restapi_object.mgmt_intercept_config.api_response).data.id}",
                "${jsondecode(restapi_object.mgmt_host_config.api_response).data.id}"
            ],
            "roleAttributes": [
                "mgmt-services"
            ]
        }
    EOF
}

resource "restapi_object" "mgmt_bind_service_policy" {
    depends_on = [restapi_object.mgmt_service]
    provider    = restapi
    path        = "/service-policies"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "mgmt-bind-policy",
            "type": "Bind",
            "semantic": "AnyOf",
            "identityRoles": [
                "#mgmt-servers"
            ],
            "postureCheckRoles": [],
            "serviceRoles": [
                "@${jsondecode(restapi_object.mgmt_service.api_response).data.id}"
            ]
        }
    EOF
}

resource "restapi_object" "mgmt_dial_service_policy" {
    depends_on = [restapi_object.mgmt_service]
    provider    = restapi
    path        = "/service-policies"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "mgmt-dial-policy",
            "type": "Dial",
            "semantic": "AnyOf",
            "identityRoles": [
                "#mgmt-clients"
            ],
            "postureCheckRoles": [],
            "serviceRoles": [
                "@${jsondecode(restapi_object.mgmt_service.api_response).data.id}"
            ]
        }
    EOF
}

resource "restapi_object" "webhook_server_identity" {
    provider    = restapi
    path        = "/identities"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "webhook-server1",
            "type": "Device",
            "isAdmin": false,
            "enrollment": {
                "ott": true
            },
            "roleAttributes": [
                "webhook-servers"
            ]
        }
    EOF
}

resource "null_resource" "enroll_webhook_server_identity" {
    depends_on = [
        restapi_object.webhook_server_identity
    ]
    provisioner "local-exec" {
        command = <<-EOF
            ziti edge enroll \
                --jwt <(echo '${jsondecode(restapi_object.webhook_server_identity.api_response).data.enrollment.ott.jwt}') \
                --out ${path.root}/.terraform/tmp/webhook-server.json
        EOF
        interpreter = ["bash", "-c"]
    }
}

data "local_file" "webhook_server_identity" {
    depends_on = [null_resource.enroll_webhook_server_identity]
    filename = "${path.root}/.terraform/tmp/webhook-server.json"
}

resource "helm_release" "webhook_server" {
    depends_on   = [null_resource.enroll_webhook_server_identity]
    chart        = "httpbin"
    version      = ">=0.1.8"
    repository   = "https://openziti.github.io/helm-charts"
    name         = "webhook-server"
    namespace    = "default"
    set {
        name = "zitiServiceName"
        value = "webhook-service"
    }
    set_sensitive {
        name = "zitiIdentityEncoding"
        value = base64encode(data.local_file.webhook_server_identity.content)
        type  = "auto"
    }
}

data "restapi_object" "intercept_v1_config_type" {
    provider    = restapi
    path = "/config-types"
    search_key = "name"
    search_value = "intercept.v1"
    results_key = "data"
    debug = true
}


resource "restapi_object" "webhook_intercept_config" {
    depends_on = [data.restapi_object.intercept_v1_config_type]
    provider    = restapi
    path        = "/configs"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "webhook-intercept-config",
            "configTypeId": "${jsondecode(data.restapi_object.intercept_v1_config_type.api_response).data.id}",
            "data": {
                "protocols": ["tcp"],
                "addresses": ["webhook2.ziti"], 
                "portRanges": [{"low":80, "high":80}]
            }
        }
    EOF
}

data "restapi_object" "host_v1_config_type" {
    provider    = restapi
    path = "/config-types"
    search_key = "name"
    search_value = "host.v1"
    results_key = "data"
    debug = true
}


resource "restapi_object" "webhook_host_config" {
    provider    = restapi
    path        = "/configs"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "webhook-host-config",
            "configTypeId": "${jsondecode(data.restapi_object.host_v1_config_type.api_response).data.id}",
            "data": {
                "protocol": "tcp",
                "address": "httpbin",
                "port": 8080
            }
        }
    EOF
}

resource "restapi_object" "webhook_service" {
    depends_on = [restapi_object.webhook_intercept_config,restapi_object.webhook_host_config]
    provider    = restapi
    path        = "/services"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "webhook-service",
            "encryptionRequired": true,
            "configs": [
                "${jsondecode(restapi_object.webhook_intercept_config.api_response).data.id}",
                "${jsondecode(restapi_object.webhook_host_config.api_response).data.id}"
            ],
            "roleAttributes": [
                "webhook-services"
            ]
        }
    EOF
}

resource "restapi_object" "webhook_bind_service_policy" {
    depends_on = [restapi_object.webhook_service]
    provider    = restapi
    path        = "/service-policies"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "webhook-bind-policy",
            "type": "Bind",
            "semantic": "AnyOf",
            "identityRoles": [
                "#webhook-servers"
            ],
            "postureCheckRoles": [],
            "serviceRoles": [
                "@${jsondecode(restapi_object.webhook_service.api_response).data.id}"
            ]
        }
    EOF
}

resource "restapi_object" "webhook_dial_service_policy" {
    depends_on = [restapi_object.webhook_service]
    provider    = restapi
    path        = "/service-policies"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "webhook-dial-policy",
            "type": "Dial",
            "semantic": "AnyOf",
            "identityRoles": [
                "#webhook-clients"
            ],
            "postureCheckRoles": [],
            "serviceRoles": [
                "@${jsondecode(restapi_object.webhook_service.api_response).data.id}"
            ]
        }
    EOF
}

resource "restapi_object" "public_edge_router_policy" {
    provider    = restapi
    path        = "/edge-router-policies"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "public-routers",
            "semantic": "AnyOf",
            "edgeRouterRoles": [
                "#public-routers"
            ],
            "identityRoles": [
                "#all"
            ]
        }
    EOF
}

resource "restapi_object" "public_service_edge_router_policy" {
    provider    = restapi
    path        = "/service-edge-router-policies"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "public-routers",
            "semantic": "AnyOf",
            "edgeRouterRoles": [
                "#public-routers"
            ],
            "serviceRoles": [
                "#all"
            ]
        }
    EOF
}

# resource "null_resource" "kubeconfig_ansible_playbook" {
#     depends_on = [
#         linode_lke_cluster.linode_lke,
#         restapi_object.k8sapi_service
#     ]
#     provisioner "local-exec" {
#         command = <<-EOF
#             ansible-playbook -vvv ./ansible-playbooks/kubeconfig.yaml
#         EOF
#         environment = {
#             K8S_AUTH_KUBECONFIG = "../kube-config"
#         }
#     }
# }
