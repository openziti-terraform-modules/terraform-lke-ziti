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
        tls = {
            source = "hashicorp/tls"
            version = "4.0.4"
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

provider restapi {
    # uri                   = "https://mgmt.ziti:443/edge/management/v1"  # Ziti service address depends on a running tunneler with Ziti identity loaded
    uri                   = "https://${data.terraform_remote_state.controller_state.outputs.ziti_controller_mgmt_external_host}:443/edge/management/v1"
    cacerts_string        = (data.terraform_remote_state.controller_state.outputs.ctrl_plane_cas).data["ctrl-plane-cas.crt"]
    ziti_username         = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-user"]
    ziti_password         = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-password"]
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

resource "local_file" "client_identity_enrollment" {
    depends_on = [restapi_object.client_identity]
    content    = try(jsondecode(restapi_object.client_identity.api_response).data.enrollment.ott.jwt, "-")
    filename   = "../edge-client-${data.terraform_remote_state.k8s_state.outputs.cluster_label}.jwt"
}


data "restapi_object" "admin_identity_lookup" {
    provider     = restapi
    path         = "/identities"
    search_key   = "name"
    search_value = "Default Admin"
}

data "tls_certificate" "admin_client_cert_chain" {
    content = (data.terraform_remote_state.controller_state.outputs.admin_client_cert).data["tls.crt"]
}
resource "local_file" "write_client_cert" {
    filename = "../admin-client-cert.crt"
    content = element(data.tls_certificate.admin_client_cert_chain.certificates, (length(data.tls_certificate.admin_client_cert_chain.certificates) - 1)).cert_pem
}

resource "local_file" "write_client_cert_key" {
    filename = "../admin-client-cert.key"
    content = (data.terraform_remote_state.controller_state.outputs.admin_client_cert).data["tls.key"]
}

resource "local_file" "ctrl_plane_cas" {
    filename = "../ctrl-plane-cas.crt"
    content = (data.terraform_remote_state.controller_state.outputs.ctrl_plane_cas).data["ctrl-plane-cas.crt"]
}

resource "restapi_object" "cert_authenticator" {
    provider           = restapi
    path               = "/authenticators"
    data               = jsonencode({
        method = "cert"
        identityId = jsondecode(data.restapi_object.admin_identity_lookup.api_response).data.id
        certPem = element(data.tls_certificate.admin_client_cert_chain.certificates, (length(data.tls_certificate.admin_client_cert_chain.certificates) - 1)).cert_pem
    })
}


resource "null_resource" "kubeconfig_ansible_playbook" {
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook -vvv ./ansible-playbooks/kubeconfig.yaml
        EOF
        environment = {
            K8S_AUTH_KUBECONFIG = "../../kube-config"
        }
    }
}
