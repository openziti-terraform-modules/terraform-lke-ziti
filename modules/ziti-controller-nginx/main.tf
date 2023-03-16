resource "helm_release" "ziti_controller" {
    count            = var.install == true ? 1 : 0  # install unless false
    namespace        = var.ziti_namespace
    name             = var.ziti_controller_release
    version          = "~> 0.2"
    repository       = "https://openziti.github.io/helm-charts"
    chart            = var.ziti_charts != "" ? "${var.ziti_charts}/ziti-controller" : "ziti-controller"
    values           = [yamlencode({
        clientApi = {
            advertisedHost = "${var.client_domain_name}.${var.dns_zone}"
            advertisedPort = 443
            ingress = {
                enabled = true
                ingressClassName = "nginx"
                annotations = var.ingress_annotations
            }
            service = {
                enabled = true
                type = "ClusterIP"
            }
        }
        ctrlPlane = {
            advertisedHost = "${var.ctrl_domain_name}.${var.dns_zone}"
            advertisedPort = 443
            ingress = {
                enabled = true
                ingressClassName = "nginx"
                annotations = var.ingress_annotations
            }
            service = {
                enabled = true
                type = "ClusterIP"
            }
        }
        edgeSignerPki = {
            enabled = true
        }
        webBindingPki = {
            enabled = true
        }
        managementApi = {
            advertisedHost = "${var.mgmt_domain_name}.${var.dns_zone}"
            advertisedPort = 443
            dnsNames = [var.mgmt_dns_san]
            ingress = {
                enabled = true
                ingressClassName = "nginx"
                annotations = var.ingress_annotations
            }
            service = {
                enabled = true
                type = "ClusterIP"
            }
        }
        persistence = {
            storageClass = var.storage_class
        }
        cert-manager = {
            enabled = false
        }
        trust-manager = {
            enabled = false
        }
        ingress-nginx = {
            enabled = false
        }
    })]
}

data "kubernetes_secret" "admin_password_secret" {
    depends_on = [helm_release.ziti_controller]
    metadata {
        name = "${var.ziti_controller_release}-admin-secret"
        namespace = var.ziti_namespace
    }
}

data "kubernetes_secret" "admin_client_cert_secret" {
    depends_on = [helm_release.ziti_controller]
    metadata {
        name = "${var.ziti_controller_release}-admin-client-secret"
        namespace = var.ziti_namespace
    }
}

data "kubernetes_config_map" "ctrl_trust_bundle" {
    depends_on = [helm_release.ziti_controller]
    metadata {
        name = "${var.ziti_controller_release}-ctrl-plane-cas"
        namespace = var.ziti_namespace
    }
}
