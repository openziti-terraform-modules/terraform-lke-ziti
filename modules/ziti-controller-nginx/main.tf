data "template_file" "ziti_controller_values" {
    template = <<-EOF
        ctrlPlane:
            advertisedHost: ${var.ctrl_domain_name}.${var.cluster_domain_name}
            advertisedPort: 443
            service:
                enabled: true
                type: ClusterIP
            ingress:
                enabled: true
                ingressClassName: nginx
                annotations:
                    kubernetes.io/ingress.allow-http: "false"
                    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
                    nginx.ingress.kubernetes.io/secure-backends: "true"

        # enabling a separate CA for the edge signer allows us to manage the admin
        # user's client certificate
        edgeSignerPki:
            enabled: true

        webBindingPki:
        # -- generate a separate PKI root of trust for web bindings, i.e., client,
        # management, and prometheus APIs
            enabled: true

        clientApi:
            advertisedHost: ${var.client_domain_name}.${var.cluster_domain_name}
            advertisedPort: 443
            service:
                enabled: true
                type: ClusterIP
            ingress:
                enabled: true
                ingressClassName: nginx
                annotations:
                    kubernetes.io/ingress.allow-http: "false"
                    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
                    nginx.ingress.kubernetes.io/secure-backends: "true"

        managementApi:
            advertisedHost: ${var.mgmt_domain_name}.${var.cluster_domain_name}
            advertisedPort: 443
            dnsNames:
                - ${var.mgmt_dns_san}
            service:
                enabled: true
            ingress:
                enabled: true
                ingressClassName: nginx
                annotations:
                    kubernetes.io/ingress.allow-http: "false"
                    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
                    nginx.ingress.kubernetes.io/secure-backends: "true"

        persistence:
            storageClass: linode-block-storage  # append "-keep" to class name to preserve after release

        # don't install sub-charts because they're already installed by Terraform with
        # special configuration for this plan
        cert-manager:
            enabled: false
        trust-manager:
            enabled: false
        ingress-nginx:
            enabled: false
        EOF
}

resource "helm_release" "ziti_controller" {
    count = var.install ? 1 : 0  # install unless false
    namespace        = var.ziti_namespace
    name             = var.ziti_controller_release
    version          = "~> 0.2"
    repository       = "https://openziti.github.io/helm-charts"
    chart            = var.ziti_charts != "" ? "${var.ziti_charts}/ziti-controller" : "ziti-controller"
    values           = [data.template_file.ziti_controller_values.rendered]
}

data "kubernetes_secret" "admin_password_secret" {
    metadata {
        name = "${var.ziti_controller_release}-admin-secret"
        namespace = var.ziti_namespace
    }
}

data "kubernetes_secret" "admin_client_cert_secret" {
    metadata {
        name = "${var.ziti_controller_release}-admin-client-secret"
        namespace = var.ziti_namespace
    }
}

data "kubernetes_config_map" "ctrl_trust_bundle" {
    metadata {
        name = "${var.ziti_controller_release}-ctrl-plane-cas"
        namespace = var.ziti_namespace
    }
}
