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
    }
}

provider "linode" {
    token = var.LINODE_TOKEN
}

provider "helm" {
    repository_config_path = "${path.root}/.helm/repositories.yaml" 
    repository_cache       = "${path.root}/.helm"
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

resource "kubernetes_namespace" ziti {
    metadata {
        name = var.ziti_namespace
    }
}

resource "helm_release" "trust_manager" {
    depends_on   = [
        module.cert_manager,
        kubernetes_namespace.ziti
    ]
    chart      = "trust-manager"
    repository = "https://charts.jetstack.io"
    name       = "trust-manager"
    version      = "<0.5"
    namespace  = module.cert_manager.namespace
    set {
        name = "app.trust.namespace"
        value = var.ziti_namespace
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

# find the external IP of the Nodebalancer provisioned for ingress-nginx
data "kubernetes_service" "ingress_nginx_controller" {
    depends_on   = [helm_release.ingress_nginx]
    metadata {
        name = "ingress-nginx-controller"
        namespace = "ingress-nginx"
    }
}

resource "linode_domain" "cluster_zone" {
    type      = "master"
    domain    = var.cluster_domain_name
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

module "ziti_controller" {
    depends_on       = [
        module.cert_manager, 
        helm_release.trust_manager, 
        helm_release.ingress_nginx
    ]
    source = "../modules/ziti-controller-nginx"
    ziti_charts = var.ziti_charts
    ziti_controller_release = var.ziti_controller_release
    ziti_namespace = var.ziti_namespace
    cluster_domain_name = var.cluster_domain_name
}

data "template_file" "ziti_console_values" {
    template = "${file("helm-chart-values/values-ziti-console.yaml")}"
    vars = {
        cluster_issuer = var.cluster_issuer_name
        cluster_domain_name = var.cluster_domain_name
        controller_namespace = var.ziti_namespace
        controller_release = var.ziti_controller_release
        console_release = var.ziti_console_release
    }
}

resource "helm_release" "ziti_console" {
    depends_on       = [helm_release.ingress_nginx]
    name             = var.ziti_console_release
    namespace        = var.ziti_namespace
    repository       = "https://openziti.github.io/helm-charts"
    chart            = var.ziti_charts != "" ? "${var.ziti_charts}/ziti-console" : "ziti-console"
    version          = "<0.3"
    values           = [data.template_file.ziti_console_values.rendered]
}

resource "null_resource" "wait_for_dns" {
    depends_on = [linode_domain_record.wildcard_record]
    # triggers = {
    #     always_run = "${timestamp()}"
    # }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook -vvv ./ansible-playbooks/wait-for-nodebalancer-dns.yaml \
                -e client_dns=client.${var.cluster_domain_name} \
                -e nodebalancer_ip=${data.kubernetes_service.ingress_nginx_controller.status.0.load_balancer.0.ingress.0.ip}
        EOF
    }
}
