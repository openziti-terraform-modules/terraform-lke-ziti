resource "local_file" "ctrl_plane_cas" {
    content  = "${data.kubernetes_config_map.ctrl_trust_bundle.data["ctrl-plane-cas.crt"]}"
    filename = "${path.module}/.terraform/tmp/ctrl-plane-cas.crt"
}

# resource "local_file" "admin_secret" {
#     content  = yamlencode(data.kubernetes_secret.admin_secret.data)
#     filename = "${path.root}/.terraform/tmp/admin-secret.yml"
# }

output "ziti_admin_user" {
    sensitive = true
    value = "${data.kubernetes_secret.admin_secret.data["admin-user"]}"
}

output "ziti_admin_password" {
    sensitive = true
    value = "${data.kubernetes_secret.admin_secret.data["admin-password"]}"
}

output "ziti_controller_mgmt_internal_host" {
    value = "${var.ziti_controller_release}-mgmt.${var.ziti_namespace}.svc"
}

