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
        digitalocean = {
            source = "digitalocean/digitalocean"
            version = "2.27.1"
        }
    }
}

provider "linode" {
    token = var.LINODE_TOKEN
}

provider "digitalocean" {
    token = var.DO_TOKEN
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
    solvers = [
        {
            http01 = {
                ingress = {
                    class = "nginx"
                }
            },
        },
        {
            selector = {
                dnsZones = [var.dns_zone]
            },
            dns01 = {
                digitalocean = {
                    tokenSecretRef = {
                        key = "access-token"
                        name = "digitalocean-dns"
                    }
                }
            }
        }
    ]
}

resource "kubernetes_secret" "digitalocean_token" {
    type = "Opaque"
    metadata {
        name      = "digitalocean-dns"
        namespace = "cert-manager"
    }
    data = {
        token = var.DO_TOKEN
    }
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

resource "helm_release" "ingress_nginx" {
    depends_on       = [module.cert_manager]
    name             = "ingress-nginx"
    version          = "<5"
    namespace        = "ingress-nginx"
    create_namespace = true
    repository       = "https://kubernetes.github.io/ingress-nginx"
    chart            = "ingress-nginx"
    values           = [yamlencode({
        controller = {
            extraArgs = {
                enable-ssl-passthrough = "true"
            }
        }
    })]
}

# find the external IP of the Nodebalancer provisioned for ingress-nginx
data "kubernetes_service" "ingress_nginx_controller" {
    depends_on   = [helm_release.ingress_nginx]
    metadata {
        name = "ingress-nginx-controller"
        namespace = "ingress-nginx"
    }
}

resource "digitalocean_domain" "cluster_zone" {
    name = var.dns_zone
}

resource "digitalocean_record" "wildcard_record" {
    domain    = digitalocean_domain.cluster_zone.id
    name      = "*"
    type      = "A"
    value     = data.kubernetes_service.ingress_nginx_controller.status.0.load_balancer.0.ingress.0.ip
    ttl       = var.wildcard_ttl_sec
}

resource "terraform_data" "wait_for_dns" {
    depends_on = [digitalocean_record.wildcard_record]
    triggers_replace = [
        timestamp()
    ]
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook -vvv ./ansible-playbooks/wait-for-nodebalancer-dns.yaml \
                -e client_dns=wildcard.${var.dns_zone} \
                -e nodebalancer_ip=${data.kubernetes_service.ingress_nginx_controller.status.0.load_balancer.0.ingress.0.ip}
        EOF
    }
}
