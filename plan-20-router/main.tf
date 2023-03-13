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
    uri                   = "https://${data.terraform_remote_state.lke_state.outputs.ziti_controller_mgmt_external_host}:443/edge/management/v1"
    cacerts_file          = "${path.root}/.terraform/ctrl-plane-cas.crt"
    ziti_username         = "${data.terraform_remote_state.lke_state.outputs.ziti_admin_username}"
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

module "ziti_router_public" {
    source = "../modules/ziti-router-nginx"
    ctrl_endpoint     = "${data.terraform_remote_state.lke_state.outputs.ziti_controller_ctrl_internal_host}:443"
    router1_edge      = "${var.router1_edge_domain_name}.${data.terraform_remote_state.lke_state.outputs.cluster_domain_name}"
    router1_transport = "${var.router1_transport_domain_name}.${data.terraform_remote_state.lke_state.outputs.cluster_domain_name}"
    public_router_role = "public-routers"
}
