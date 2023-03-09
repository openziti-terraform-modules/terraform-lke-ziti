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
        linode = {
            source  = "linode/linode"
            version = "1.29.4"
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
        openziti = {
            source = "qrkourier/restapi"
            version = "~> 1.19.0"
        }
    }
}

provider openziti {
    uri                   = "https://${var.mgmt_domain_name}.${var.domain_name}:${var.mgmt_port}"
    debug                 = true
    create_returns_object = true
    write_returns_object  = false
    insecure              = false
    cacerts_string        = "${data.kubernetes_config_map.ctrl_trust_bundle.data["ctrl-plane-cas.crt"]}"
    ziti_username         = "${data.kubernetes_secret.admin_secret.data["admin-user"]}"
    ziti_password         = "${data.kubernetes_secret.admin_secret.data["admin-password"]}"
}

provider "linode" {
    token = var.token
}

resource "linode_lke_cluster" "linode_lke" {
    label       = var.label
    k8s_version = var.k8s_version
    region      = var.region
    tags        = var.tags

    dynamic "pool" {
        for_each = var.pools
        content {
            type  = pool.value["type"]
            count = pool.value["count"]
        }
    }
}

provider "helm" {
    kubernetes {
        host                   = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.server
        token                  = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).users[0].user.token
        cluster_ca_certificate = base64decode(yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.certificate-authority-data)
    }
}

provider "kubernetes" {
    host                   = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.server
    token                  = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).users[0].user.token
    cluster_ca_certificate = base64decode(yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.certificate-authority-data)
}

provider "kubectl" {     # duplcates config of provider "kubernetes" for cert-manager module
    host                   = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.server
    token                  = yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).users[0].user.token
    cluster_ca_certificate = base64decode(yamldecode(base64decode(linode_lke_cluster.linode_lke.kubeconfig)).clusters[0].cluster.certificate-authority-data)
    load_config_file       = false
}

module "cert_manager" {
    depends_on = [linode_lke_cluster.linode_lke]
    source        = "terraform-iaac/cert-manager/kubernetes"

    cluster_issuer_email                   = var.email
    cluster_issuer_name                    = var.cluster_issuer_name
    cluster_issuer_server                  = var.cluster_issuer_server
    cluster_issuer_private_key_secret_name = "${var.cluster_issuer_name}-secret"
    additional_set = [{
        name = "enableCertificateOwnerRef"
        value = "true"
    }]
}

resource "kubernetes_namespace" ziti_controller {
    metadata {
        name = var.ziti_controller_namespace
    }
}

resource "helm_release" "trust_manager" {
    depends_on   = [module.cert_manager, kubernetes_namespace.ziti_controller]
    chart      = "trust-manager"
    repository = "https://charts.jetstack.io"
    name       = "trust-manager"
    version      = "<0.5"
    namespace  = module.cert_manager.namespace
    set {
        name = "app.trust.namespace"
        value = var.ziti_controller_namespace
    }
}

data "template_file" "ingress_nginx_values" {
    template = "${file("helm-chart-values/values-ingress-nginx.yaml")}"
}

resource "helm_release" "ingress_nginx" {
    depends_on       = [module.cert_manager]
    name             = "ingress-nginx"
    version          = "<5"
    namespace        = "ingress-nginx"
    create_namespace = true
    repository       = "https://kubernetes.github.io/ingress-nginx"
    chart            = "ingress-nginx"
    values           = [data.template_file.ingress_nginx_values.rendered]
}

# discover the external IP of the Nodebalancer provisioned for the ingress-nginx
# Service
data "kubernetes_service" "ingress_nginx_controller" {
    depends_on   = [helm_release.ingress_nginx]
    metadata {
        name = "ingress-nginx-controller"
        namespace = "ingress-nginx"
    }
}

resource "linode_domain" "cluster_zone" {
    type      = "master"
    domain    = var.domain_name
    soa_email = var.email
    tags      = var.tags
}

resource "linode_domain_record" "wildcard_record" {
    domain_id   = linode_domain.cluster_zone.id
    name        = "*"
    record_type = "A"
    target      = data.kubernetes_service.ingress_nginx_controller.status.0.load_balancer.0.ingress.0.ip
    ttl_sec     = var.wildcard_ttl_sec
}

data "template_file" "ziti_controller_values" {
    template = "${file("helm-chart-values/values-ziti-controller.yaml")}"
    vars = {
        ctrl_port = var.ctrl_port
        client_port = var.client_port
        mgmt_port = var.mgmt_port
        ctrl_domain_name = var.ctrl_domain_name
        client_domain_name = var.client_domain_name
        mgmt_domain_name = var.mgmt_domain_name
        domain_name = var.domain_name
    }
}

data "template_file" "ziti_router1_values" {
    template = "${file("helm-chart-values/values-ziti-router1.yaml")}"
    vars = {
        ctrl_endpoint = "${helm_release.ziti_controller.name}-ctrl.${var.ziti_controller_namespace}.svc:${var.ctrl_port}"
        # ctrl_endpoint = "${var.ctrl_domain_name}.${var.domain_name}:${var.ctrl_port}"
        router1_edge = "${var.router1_edge_domain_name}.${var.domain_name}"
        router1_transport = "${var.router1_transport_domain_name}.${var.domain_name}"
    }
}

resource "helm_release" "ziti_controller" {
    depends_on       = [
        helm_release.trust_manager, 
        helm_release.ingress_nginx
    ]
    namespace        = var.ziti_controller_namespace
    create_namespace = true
    name             = "ziti-controller"
    version          = "<0.2"
    repository       = "https://openziti.github.io/helm-charts"
    chart            = "ziti-controller"
    values           = [data.template_file.ziti_controller_values.rendered]
}

data "kubernetes_secret" "admin_secret" {
    metadata {
        name = "${helm_release.ziti_controller.name}-admin-secret"
        namespace = helm_release.ziti_controller.namespace
    }
}

data "kubernetes_config_map" "ctrl_trust_bundle" {
    metadata {
        name = "${helm_release.ziti_controller.name}-ctrl-plane-cas"
        namespace = helm_release.ziti_controller.namespace
    }
}


data "template_file" "ziti_console_values" {
    template = "${file("helm-chart-values/values-ziti-console.yaml")}"
    vars = {
        cluster_issuer = var.cluster_issuer_name
        domain_name = var.domain_name
        console_domain_name = var.console_domain_name
        controller_namespace = helm_release.ziti_controller.namespace
        controller_release = helm_release.ziti_controller.name
        console_release = var.ziti_console_release
        mgmt_port = var.mgmt_port
    }
}

resource "helm_release" "ziti_console" {
    depends_on       = [helm_release.ingress_nginx]
    name             = var.ziti_console_release
    namespace        = "ziti-console"
    create_namespace = true
    repository       = "https://openziti.github.io/helm-charts"
    chart            = "ziti-console"
    version          = "<0.3"
    values           = [data.template_file.ziti_console_values.rendered]
}

resource "null_resource" "wait_for_dns" {
    depends_on = [linode_domain_record.wildcard_record]
    triggers = {
        always_run = "${timestamp()}"
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook -vvv ./ansible-playbooks/wait-for-nodebalancer-dns.yaml \
                -e client_dns=${var.client_domain_name}.${var.domain_name} \
                -e nodebalancer_ip=${data.kubernetes_service.ingress_nginx_controller.status.0.load_balancer.0.ingress.0.ip}
        EOF
    }
}

resource "restapi_object" "router1" {
    depends_on  = [null_resource.wait_for_dns]
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

data "restapi_object" "router1" {
    provider = openziti
    path = "/edge-routers"
    search_key = "name"
    search_value = "router1"
    results_key = "data"
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
