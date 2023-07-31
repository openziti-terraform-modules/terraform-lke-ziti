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

provider "helm" {
  repository_config_path = "${path.root}/.helm/repositories.yaml"
  repository_cache       = "${path.root}/.helm"
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
  depends_on    = [data.restapi_object.router1_identity_lookup]
  provider      = restapi
  path          = "/identities"
  update_method = "PATCH"
  data = jsonencode({
    id = jsondecode(data.restapi_object.router1_identity_lookup.api_response).data.id
    roleAttributes = [
      "mgmt-hosts",
      "k8sapi-hosts",
      "helloweb-hosts"
    ]
  })
}


module "helloweb_service" {
  source = "github.com/openziti-terraform-modules/terraform-openziti-service?ref=v0.1.0"
  # normally the address should be computed from the Helm release attributes,
  # but when testing a local chart, we can hardcode the cluster service
  # address
  upstream_address = var.ziti_charts != "" ? "helloweb-host-hello-toy.ziti.svc" : "${helm_release.helloweb_host.name}-${helm_release.helloweb_host.chart}.${helm_release.helloweb_host.namespace}.svc"

  upstream_port     = 80
  intercept_address = "helloweb.ziti"
  intercept_port    = 80
  role_attributes   = ["helloweb-services"]
  name              = "helloweb"
}

module "mgmt_service" {
  source            = "github.com/openziti-terraform-modules/terraform-openziti-service?ref=v0.1.0"
  upstream_address  = data.terraform_remote_state.controller_state.outputs.ziti_controller_mgmt_internal_host
  upstream_port     = 443
  intercept_address = "mgmt.ziti"
  intercept_port    = 443
  role_attributes   = ["mgmt-services"]
  name              = "mgmt"
}

module "k8sapi_service" {
  source            = "github.com/openziti-terraform-modules/terraform-openziti-service?ref=v0.1.0"
  upstream_address  = "kubernetes.default.svc"
  upstream_port     = 443
  intercept_address = "kubernetes.default.svc"
  intercept_port    = 443
  role_attributes   = ["k8sapi-services"]
  name              = "k8sapi"
}

resource "restapi_object" "testapi_host_identity" {
  provider = restapi
  path     = "/identities"
  data = jsonencode({
    name    = "testapi-host"
    type    = "Device"
    isAdmin = false
    enrollment = {
      ott = true
    }
    roleAttributes = ["testapi-hosts"]
  })
}

# resource "null_resource" "enroll_testapi_host_identity" {
#     depends_on = [restapi_object.testapi_host_identity]
#     provisioner "local-exec" {
#         command = <<-EOF
#             ziti edge enroll \
#                 --jwt <(echo '${jsondecode(restapi_object.testapi_host_identity.api_response).data.enrollment.ott.jwt}') \
#                 --out ${path.root}/.terraform/testapi-host.json
#         EOF
#         interpreter = ["bash", "-c"]
#     }
# }

# resource "restapi_object" "testapi_host_enrollment" {
#     provider           = restapi
#     path               = "/enrollment"
#     data               = jsonencode({
#         method = "ott"
#         expiresAt = timeadd(timestamp(), "1h")
#         identityId = restapi_object.testapi_host_identity.api_data.data.id
#     })
# }

# data "local_file" "testapi_host_identity" {
#     depends_on = [null_resource.enroll_testapi_host_identity]
#     filename   = "${path.root}/.terraform/testapi-host.json"
# }

# resource "local_file" "testapi_host_identity_enrollment" {
#     depends_on = [restapi_object.testapi_host_identity]
#     content    = try(jsondecode(restapi_object.testapi_host_identity.api_response).data.enrollment.ott.jwt, "-")
#     filename   = "../testapi-host-${data.terraform_remote_state.k8s_state.outputs.cluster_label}.jwt"
# }
resource "helm_release" "helloweb_host" {
  chart      = var.ziti_charts != "" ? "${var.ziti_charts}/hello-toy" : "hello-toy"
  version    = ">=2.1.0"
  repository = "https://openziti.github.io/helm-charts"
  name       = "helloweb-host"
  namespace  = "ziti" # not necessary to share a namespace with the controller or router, but convenient for debugging
  # wait          = false  # hooks don't run if wait=true!?
}

resource "helm_release" "testapi_host" {
  depends_on = [
    module.testapi_service
  ]
  chart      = var.ziti_charts != "" ? "${var.ziti_charts}/httpbin" : "httpbin"
  version    = ">=0.1.8"
  repository = "https://openziti.github.io/helm-charts"
  name       = "testapi-host"
  namespace  = "ziti" # not necessary to share a namespace with the controller or router, but convenient for debugging
  wait       = false  # hooks don't run if wait=true!?
  set {
    name  = "zitiServiceName"
    value = "testapi-service"
  }
  set_sensitive {
    name  = "zitiEnrollment"
    value = try(jsondecode(restapi_object.testapi_host_identity.api_response).data.enrollment.ott.jwt, "-")
    type  = "auto"
  }
}

# This Ziti service is hosted by the Ziti fork of go-httpbin which uses the Ziti
# Edge SDK with a Ziti identity to listen on the overlay instead of the normal
# IP network.
module "testapi_service" {
  source = "github.com/openziti-terraform-modules/terraform-openziti-service?ref=v0.1.0"
  # source                    = "/home/kbingham/Sites/netfoundry/github/terraform-openziti-service"
  upstream_address  = "noop" # Ziti hosted servers have no address
  upstream_port     = 54321  # Ziti hosted servers have no port
  intercept_address = "testapi.ziti"
  intercept_port    = 80
  role_attributes   = ["testapi-services"]
  name              = "testapi"
}

module "public_routers" {
  source = "github.com/openziti-terraform-modules/terraform-openziti-router-policies?ref=v0.1.1"
  # source                    = "/home/kbingham/Sites/netfoundry/github/terraform-openziti-router-policies"
  router_roles = ["#public-routers"]
}
