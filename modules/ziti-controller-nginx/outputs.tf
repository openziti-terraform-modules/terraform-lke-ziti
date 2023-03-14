output "ctrl_plane_cas" {
    value = "${data.kubernetes_config_map.ctrl_trust_bundle.data}"
}

output "admin_client_cert" {
    value  = "${data.kubernetes_secret.admin_client_cert_secret}"
}

output "ziti_admin_password" {
    sensitive = true
    value = "${data.kubernetes_secret.admin_password_secret.data}"
}

output "ziti_controller_ctrl_internal_host" {
    value = "${var.ziti_controller_release}-ctrl.${var.ziti_namespace}.svc"
}

output "ziti_controller_mgmt_internal_host" {
    value = "${var.ziti_controller_release}-mgmt.${var.ziti_namespace}.svc"
}

output "ziti_controller_client_external_host" {
    value = "${var.client_domain_name}.${var.dns_zone}"
}

output "ziti_controller_mgmt_external_host" {
    value = "${var.mgmt_domain_name}.${var.dns_zone}"
}
