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
        # download: https://github.com/qrkourier/terraform-provider-restapi/releases/latest
        # install: ~/
        openziti = {
            source = "qrkourier/restapi"
            version = "~> 1.20.0"
        }
    }
}

data "terraform_remote_state" "lke_state" {
    backend = "local"
    config = {
        path = "${path.root}/../plan-10-lke/terraform.tfstate"
    }
}

provider openziti {
    uri                   = "${data.terraform_remote_state.lke_state.outputs.ziti_controller_mgmt}"
    debug                 = true
    create_returns_object = true
    write_returns_object  = false
    insecure              = false
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
    provider    = openziti
    path        = "/edge-routers"
    read_search = {
        results_key = "data"
    }
    data = <<-EOF
        {
            "name": "router1",
            "isTunnelerEnabled": true,
            "roleAttributes": [
                "public-routers"
            ]
        }
    EOF
}

# the management API doesn't return the created or updated properties, and this
# plugin isn't yet smart enough to go look up the new state in the API by
# following the link to the ID of the resource. So a pair of Terraform
# resource+data source are necessary to read the changed state.
# data "restapi_object" "router1" {
#     depends_on = [restapi_object.router1]
#     provider = openziti
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
