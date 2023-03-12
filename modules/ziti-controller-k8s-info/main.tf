data "kubernetes_secret" "admin_secret" {
    metadata {
        name = "${var.ziti_controller_release}-admin-secret"
        namespace = var.ziti_namespace
    }
}

data "kubernetes_config_map" "ctrl_trust_bundle" {
    metadata {
        name = "${var.ziti_controller_release}-ctrl-plane-cas"
        namespace = var.ziti_namespace
    }
}

