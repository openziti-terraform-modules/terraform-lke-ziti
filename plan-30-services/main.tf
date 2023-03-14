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

data "terraform_remote_state" "k8s_state" {
    backend = "local"
    config = {
        path = "${path.root}/../plan-10-k8s/terraform.tfstate"
    }
}

data "terraform_remote_state" "controller_state" {
    backend = "local"
    config = {
        path = "${path.root}/../plan-15-controller/terraform.tfstate"
    }
}

provider restapi {
    uri                   = "https://${data.terraform_remote_state.controller_state.outputs.ziti_controller_mgmt_external_host}:443/edge/management/v1"
    cacerts_string        = (data.terraform_remote_state.controller_state.outputs.ctrl_plane_cas).data["ctrl-plane-cas.crt"]
    ziti_username         = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-user"]
    ziti_password         = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-password"]
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

# find the id of the Router's tunnel identity so we can declare it in the next
# resource for import and ongoing PATCH management
data "restapi_object" "router1_identity_lookup" {
    provider     = restapi
    path         = "/identities"
    search_key   = "name"
    search_value = "router1"
}

resource "restapi_object" "router1_identity" {
    depends_on         = [data.restapi_object.router1_identity_lookup]
    provider           = restapi
    path               = "/identities"
    update_method      = "PATCH"
    data               = jsonencode({
        id             = jsondecode(data.restapi_object.router1_identity_lookup.api_response).data.id
        roleAttributes = [
            "mgmt-hosts",
            "k8sapi-hosts"
        ]
    })
}

resource "restapi_object" "client_identity" {
    debug              = true
    provider           = restapi
    path               = "/identities"
    data               = jsonencode({
        name           = "edge-client"
        type           = "Device"
        isAdmin        = false
        enrollment     = {
            ott        = true
        }
        roleAttributes = [
            "testapi-clients",
            "k8sapi-clients",
            "mgmt-clients"
        ]
    })
}

resource "local_file" "client_identity" {
    depends_on = [restapi_object.client_identity]
    content    = try(jsondecode(restapi_object.client_identity.api_response).data.enrollment.ott.jwt, "dummystring")
    filename   = "/tmp/lke-edge-client.jwt"
}

module "mgmt_service" {
    source                   = "../modules/simple-tunneled-service"
    upstream_address         = data.terraform_remote_state.controller_state.outputs.ziti_controller_mgmt_internal_host
    upstream_port            = 443
    intercept_address        = "mgmt.ziti"
    intercept_port           = 443
    role_attributes          = ["mgmt-services"]
    name                     = "mgmt"
}

module "k8sapi_service" {
    source                   = "../modules/simple-tunneled-service"
    upstream_address         = "kubernetes.default.svc"
    upstream_port            = 443
    intercept_address        = "kubernetes.default.svc"
    intercept_port           = 443
    role_attributes          = ["k8sapi-services"]
    name                     = "k8sapi"
}

resource "restapi_object" "testapi_host_identity" {
    provider           = restapi
    path               = "/identities"
    data               = jsonencode({
        name           = "testapi-host"
        type           = "Device"
        isAdmin        = false
        enrollment     = {
            ott        = true
        }
        roleAttributes = ["testapi-hosts"]
    })
}

resource "null_resource" "enroll_testapi_host_identity" {
    depends_on = [restapi_object.testapi_host_identity]
    provisioner "local-exec" {
        command = <<-EOF
            ziti edge enroll \
                --jwt <(echo '${jsondecode(restapi_object.testapi_host_identity.api_response).data.enrollment.ott.jwt}') \
                --out ${path.root}/.terraform/testapi-host.json
        EOF
        interpreter = ["bash", "-c"]
    }
}

data "local_file" "testapi_host_identity" {
    depends_on = [null_resource.enroll_testapi_host_identity]
    filename   = "${path.root}/.terraform/testapi-host.json"
}

resource "helm_release" "testapi_host" {
    depends_on    = [
        null_resource.enroll_testapi_host_identity,
        module.testapi_service
    ]
    chart         = var.ziti_charts != "" ? "${var.ziti_charts}/httpbin" : "httpbin"
    version       = ">=0.1.8"
    repository    = "https://openziti.github.io/helm-charts"
    name          = "testapi-host"
    namespace     = "default"
    set             {
        name      = "zitiServiceName"
        value     = "testapi-service"
    }
    set_sensitive   {
        name      = "zitiIdentityEncoding"
        value     = base64encode(data.local_file.testapi_host_identity.content)
        type      = "auto"
    }
}

module "testapi_service" {
    source                   = "../modules/simple-tunneled-service"
    upstream_address         = "httpbin.default.svc"
    upstream_port            = 8080
    intercept_address        = "testapi.ziti"
    intercept_port           = 80
    role_attributes          = ["testapi-services"]
    name                     = "testapi"
}

module "public_routers" {
    source       = "../modules/public-router-policies"
    router_roles = ["#public-routers"]
}
