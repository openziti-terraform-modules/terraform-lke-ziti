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
            version = "~> 1.22.0"
        }
    }
}

data "terraform_remote_state" "lke_state" {
    backend = "local"
    config = {
        path = "${path.root}/../plan-10-k8s/terraform.tfstate"
    }
}

provider restapi {
    uri                   = "https://${data.terraform_remote_state.lke_state.outputs.ziti_controller_external_host}:${data.terraform_remote_state.lke_state.outputs.mgmt_port}/edge/management/v1"
    cacerts_file          = "${path.root}/../plan-10-k8s/.terraform/tmp/ctrl-plane-cas.crt"
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


# find the id of the Router's tunnel identity so we can declare it in the next
# resource for import and ongoing PATCH management
data "restapi_object" "router1_identity_lookup" {
    provider     = restapi
    path         = "/identities"
    search_key   = "name"
    search_value = "router1"
}

resource "restapi_object" "router1_identity" {
    depends_on    = [data.restapi_object.router1_identity_lookup]
    debug         = true
    provider      = restapi
    path          = "/identities"
    update_method = "PATCH"
    data = <<-EOF
        {
            "id": "${jsondecode(data.restapi_object.router1_identity_lookup.api_response).data.id}",
            "roleAttributes": [
                "mgmt-hosts",
                "k8sapi-hosts"
            ]
        }
    EOF
}

resource "restapi_object" "client_identity" {
    provider    = restapi
    path        = "/identities"
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
    data = <<-EOF
        {
            "name": "mgmt-bind-policy",
            "type": "Bind",
            "semantic": "AnyOf",
            "identityRoles": [
                "#mgmt-hosts"
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

resource "restapi_object" "k8sapi_intercept_config" {
    depends_on = [data.restapi_object.intercept_v1_config_type]
    provider    = restapi
    path        = "/configs"
    data = <<-EOF
        {
            "name": "k8sapi-intercept-config",
            "configTypeId": "${jsondecode(data.restapi_object.intercept_v1_config_type.api_response).data.id}",
            "data": {
                "protocols": ["tcp"],
                "addresses": ["kubernetes.default.svc"], 
                "portRanges": [{"low":443, "high":443}]
            }
        }
    EOF
}

resource "restapi_object" "k8sapi_host_config" {
    provider    = restapi
    path        = "/configs"
    data = <<-EOF
        {
            "name": "k8sapi-host-config",
            "configTypeId": "${jsondecode(data.restapi_object.host_v1_config_type.api_response).data.id}",
            "data": {
                "protocol": "tcp",
                "address": "kubernetes.default.svc",
                "port": 443
            }
        }
    EOF
}

resource "restapi_object" "k8sapi_service" {
    depends_on = [
        restapi_object.k8sapi_intercept_config,
        restapi_object.k8sapi_host_config
    ]
    provider    = restapi
    path        = "/services"
    data = <<-EOF
        {
            "name": "k8sapi-service",
            "encryptionRequired": true,
            "configs": [
                "${jsondecode(restapi_object.k8sapi_intercept_config.api_response).data.id}",
                "${jsondecode(restapi_object.k8sapi_host_config.api_response).data.id}"
            ],
            "roleAttributes": [
                "k8sapi-services"
            ]
        }
    EOF
}

resource "restapi_object" "k8sapi_bind_service_policy" {
    depends_on = [restapi_object.k8sapi_service]
    provider    = restapi
    path        = "/service-policies"
    data = <<-EOF
        {
            "name": "k8sapi-bind-policy",
            "type": "Bind",
            "semantic": "AnyOf",
            "identityRoles": [
                "#k8sapi-hosts"
            ],
            "postureCheckRoles": [],
            "serviceRoles": [
                "@${jsondecode(restapi_object.k8sapi_service.api_response).data.id}"
            ]
        }
    EOF
}

resource "restapi_object" "k8sapi_dial_service_policy" {
    depends_on = [restapi_object.k8sapi_service]
    provider    = restapi
    path        = "/service-policies"
    data = <<-EOF
        {
            "name": "k8sapi-dial-policy",
            "type": "Dial",
            "semantic": "AnyOf",
            "identityRoles": [
                "#k8sapi-clients"
            ],
            "postureCheckRoles": [],
            "serviceRoles": [
                "@${jsondecode(restapi_object.k8sapi_service.api_response).data.id}"
            ]
        }
    EOF
}

resource "restapi_object" "webhook_host_identity" {
    provider    = restapi
    path        = "/identities"
    data = <<-EOF
        {
            "name": "webhook-host",
            "type": "Device",
            "isAdmin": false,
            "enrollment": {
                "ott": true
            },
            "roleAttributes": [
                "webhook-hosts"
            ]
        }
    EOF
}

resource "null_resource" "enroll_webhook_host_identity" {
    depends_on = [
        restapi_object.webhook_host_identity
    ]
    provisioner "local-exec" {
        command = <<-EOF
            ziti edge enroll \
                --jwt <(echo '${jsondecode(restapi_object.webhook_host_identity.api_response).data.enrollment.ott.jwt}') \
                --out ${path.root}/.terraform/webhook-host.json
        EOF
        interpreter = ["bash", "-c"]
    }
}

data "local_file" "webhook_host_identity" {
    depends_on = [null_resource.enroll_webhook_host_identity]
    filename = "${path.root}/.terraform/webhook-host.json"
}

resource "helm_release" "webhook_host" {
    depends_on   = [null_resource.enroll_webhook_host_identity]
    chart        = "httpbin"
    version      = ">=0.1.8"
    repository   = "https://openziti.github.io/helm-charts"
    name         = "webhook-host"
    namespace    = "default"
    set {
        name = "zitiServiceName"
        value = "webhook-service"
    }
    set_sensitive {
        name = "zitiIdentityEncoding"
        value = base64encode(data.local_file.webhook_host_identity.content)
        type  = "auto"
    }
}

data "restapi_object" "intercept_v1_config_type" {
    provider     = restapi
    path         = "/config-types"
    search_key   = "name"
    search_value = "intercept.v1"
}


resource "restapi_object" "webhook_intercept_config" {
    depends_on  = [data.restapi_object.intercept_v1_config_type]
    provider    = restapi
    path        = "/configs"
    data = <<-EOF
        {
            "name": "webhook-intercept-config",
            "configTypeId": "${jsondecode(data.restapi_object.intercept_v1_config_type.api_response).data.id}",
            "data": {
                "protocols": ["tcp"],
                "addresses": ["webhook.ziti"], 
                "portRanges": [{"low":80, "high":80}]
            }
        }
    EOF
}

data "restapi_object" "host_v1_config_type" {
    provider     = restapi
    path         = "/config-types"
    search_key   = "name"
    search_value = "host.v1"
}


resource "restapi_object" "webhook_host_config" {
    provider    = restapi
    path        = "/configs"
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
    data = <<-EOF
        {
            "name": "webhook-bind-policy",
            "type": "Bind",
            "semantic": "AnyOf",
            "identityRoles": [
                "#webhook-hosts"
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
