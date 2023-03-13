data "template_file" "ziti_controller_values" {
    template = "${file("helm-chart-values/values-ziti-controller.yaml")}"
    vars = {
        cluster_domain_name = var.cluster_domain_name
        ctrl_domain_name = var.ctrl_domain_name
        ctrl_port = var.ctrl_port
        client_domain_name = var.client_domain_name
        client_port = var.client_port
        mgmt_domain_name = var.mgmt_domain_name
        mgmt_port = var.mgmt_port
    }
}

resource "helm_release" "ziti_controller" {
    namespace        = var.ziti_namespace
    name             = var.ziti_controller_release
    version          = "~> 0.2"
    repository       = "https://openziti.github.io/helm-charts"
    chart            = "${var.ziti_charts}/ziti-controller"
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
