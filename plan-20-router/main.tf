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
        helm = {
            source  = "hashicorp/helm"
            version = "2.5.0"
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
    debug                 = true
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


resource "restapi_object" "router1" {
    debug       = true
    provider    = restapi
    path        = "/edge-routers"
    data = <<-EOF
        {
            "name": "router1",
            "isTunnelerEnabled": true,
            "roleAttributes": [
                "public-routers",
                "mgmt-hosts"
            ]
        }
    EOF
}

data "template_file" "ziti_router1_values" {
    template = "${file("helm-chart-values/values-ziti-router1.yaml")}"
    vars = {
        ctrl_endpoint     = "${data.terraform_remote_state.lke_state.outputs.ziti_controller_ctrl}"
        router1_edge      = "${var.router1_edge_domain_name}.${coalesce(var.domain_name, data.terraform_remote_state.lke_state.outputs.domain_name)}"
        router1_transport = "${var.router1_transport_domain_name}.${coalesce(var.domain_name, data.terraform_remote_state.lke_state.outputs.domain_name)}"
        jwt               = "${ try(jsondecode(restapi_object.router1.api_response).data.enrollmentJwt, "dummystring") }"
    }
}

resource "helm_release" "ziti_router1" {
    depends_on = [restapi_object.router1]
    name       = var.router1_release
    namespace  = "${data.terraform_remote_state.lke_state.outputs.ziti_namespace}"
    repository = "https://openziti.github.io/helm-charts"
    chart      = "ziti-router"
    version    = "<0.3"
    wait       = false  # hooks don't run if wait=true!?
    values     = [data.template_file.ziti_router1_values.rendered]
}
