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
            version = "2.0.1"
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
    # influxdb_tls_cert_path = "/etc/ssl/certs/influxdb.crt"
    # influxdb_tls_key_path = "/etc/ssl/private/influxdb.key"
    # influxdb_tls_cert_name = "influxdb-cert"
    # influxdb_tls_cert_secret = "influxdb-cert-secret"
    influxdb_admin_token = "influxdb-admin-token"
}

resource "terraform_data" "helm_update" {
    count = 1 # set to 1 to trigger helm repo update
    triggers_replace = [
        timestamp()
    ]
    provisioner "local-exec" {
        command = "helm repo update openziti"
    }
}

resource "helm_release" "influxdb2" {
    depends_on = [
        helm_release.zrok  # supports testing by putting zrok first
    ]
    name = "influxdb"
    namespace = "zrok"
    repository = "https://helm.influxdata.com/"
    chart = "influxdb2"
    version = "~> 2.1.1"
    values = [yamlencode({
        adminUser = {
            user = "admin"
            existingSecret = local.influxdb_admin_token  # created by zrok chart
            organization = "zrok"
            bucket = "zrok"
        }
        service = {
            type = "ClusterIP"
            port = 80
        }
        persistence = {
            storageClass = var.storage_class
            size = "10Gi"
        }
    })]
}

resource "kubernetes_namespace" "zrok" {
    metadata {
        name = "zrok"
        labels = {
            # this label is selected by trust-manager to sync the CA trust bundle
            "openziti.io/namespace": "enabled"
        }
    }
}

resource "helm_release" "zrok" {
    depends_on = [
        kubernetes_namespace.zrok  # ensure release is deleted before namespace so hooks can create delete jobs
    ]
    name       = "zrok"
    namespace  = "zrok"
    repository = "https://openziti.github.io/helm-charts/"
    chart      = var.ziti_charts != "" ? "${var.ziti_charts}/zrok" : "zrok"
    # version    = "~> 0.0.1"
    values     = [data.template_file.zrok_values.rendered]
}

module "influxdb_service" {
    source = "github.com/openziti-test-kitchen/terraform-openziti-service?ref=v0.1.0"
    upstream_address         = "influxdb-influxdb2.zrok.svc"
    upstream_port            = 80
    intercept_address        = "influxdb.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
    intercept_port           = 80
    role_attributes          = ["monitoring-services"]
    bind_identity_roles      = ["#monitoring-hosts"]
    dial_identity_roles      = ["#monitoring-clients"]
    name                     = "influxdb"
}

data "template_file" "zrok_values" {
    template = yamlencode({
        influxdb2 = {
            enabled = false  # declared separately in helm_release.influxdb2
            service = {
                url = "http://influxdb-influxdb2.zrok.svc"
            }
            adminUser = {
                existingSecret = local.influxdb_admin_token
            }
        }
        image = {
            repository = var.container_image_repository
            tag = var.container_image_tag
            pullPolicy = var.container_image_pull_policy
        }
        dnsZone = data.terraform_remote_state.k8s_state.outputs.dns_zone
        env = [
            # {
            #     name = "INFLUXD_TLS_CERT"
            #     value = var.influxdb_tls_cert_path
            # },
            # {
            #     name = "INFLUXD_TLS_KEY"
            #     value = var.influxdb_tls_key_path
            # }
        ]
        ziti = {
            advertisedHost = "${data.terraform_remote_state.controller_state.outputs.ziti_controller_mgmt_internal_host}"
            username = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-user"]
            password = (data.terraform_remote_state.controller_state.outputs.ziti_admin_password).data["admin-password"]
            ca_cert_configmap = data.terraform_remote_state.controller_state.outputs.ctrl_plane_cas_configmap
        }
        controller = {
            specVersion = var.zrok_controller_spec_version
            ingress = {
                enabled = true
                scheme = "http"
                className = "nginx"
                annotations = {
                    # "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
                    "cert-manager.io/cluster-issuer" = data.terraform_remote_state.k8s_state.outputs.cluster_issuer_name
                }
                hosts = [{
                    host = "${var.controller_dns_name}.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
                    paths = [{
                        path = "/"
                        pathType = "ImplementationSpecific"
                    }]
                }]
                tls = [{
                    secretName = "zrok-controller-ingress-tls"
                    hosts = [
                        "${var.controller_dns_name}.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
                    ]
                }]
            }
            persistence = {
                enabled = true
                storageClass = var.storage_class
                size = "2Gi"
            }
            metrics = {
                limits = {
                    enforcing = true
                    per_account = {
                        period = "1m"
                        limit = {
                            total = 10
                        }
                    }
                }
            }
            email = {
                host = var.email_host
                port = var.email_port
                username = var.email_username
                password = var.email_password
                from = var.email_from
            }
        }
        frontend = {
            ingress = {
                enabled = true
                scheme = "https"
                className = "nginx"
                annotations = {
                    "cert-manager.io/cluster-issuer" = data.terraform_remote_state.k8s_state.outputs.cluster_issuer_name
                    # "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
                }
                hosts = [{
                    host = "*.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
                    paths = [{
                        path = "/"
                        pathType = "ImplementationSpecific"
                    }]
                }]
                tls = [{
                    secretName = "zrok-frontend-ingress-tls"
                    hosts = [
                        "*.${data.terraform_remote_state.k8s_state.outputs.dns_zone}"
                    ]
                }]
            }
        }
    })
}

resource "local_file" "zrok_values" {
    count = 0  # set to 1 to write out the rendered values file
    filename = "/tmp/zrok-values.yaml"
    content = data.template_file.zrok_values.rendered
}