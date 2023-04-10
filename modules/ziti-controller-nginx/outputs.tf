output "ctrl_plane_cas" {
    value = data.kubernetes_config_map.ctrl_trust_bundle
}

output "ctrl_plane_cas_configmap" {
    description = "name of the configmap created by trust-manager that is sync'd to namespaces with the label 'openziti.io/namespace: enabled'"
    value = "${var.ziti_controller_release}-ctrl-plane-cas"
}

output "admin_client_cert" {
    value  = data.kubernetes_secret.admin_client_cert_secret
}

output "ziti_admin_password" {
    sensitive = true
    value = data.kubernetes_secret.admin_password_secret
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
