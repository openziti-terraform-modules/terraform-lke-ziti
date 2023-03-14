output "kubeconfig" {
    value = data.terraform_remote_state.lke_state.outputs.kubeconfig
    sensitive = true
}

output "dns_zone" {
    description = "consumed by router plan to build ingress names"
    value = data.terraform_remote_state.lke_state.outputs.dns_zone
}

output "ziti_namespace" {
    description = "consumed by router plan to install release in same namespace as controller which is convenient but not necessary"
    value = data.terraform_remote_state.lke_state.outputs.ziti_namespace
}

output "ziti_admin_password" {
    sensitive = true
    value     = module.ziti_controller.ziti_admin_password
}

output "ctrl_plane_cas" {
    value = module.ziti_controller.ctrl_plane_cas
}

resource "local_file" "ctrl_plane_cas" {
    depends_on = [module.ziti_controller]
    filename     = "../plan-20-router/.terraform/ctrl-plane-cas.crt"
    content      = "${module.ziti_controller.ctrl_plane_cas["data"]["ctrl-plane-cas.crt"]}"
}

output "admin_client_cert" {
    sensitive = true
    value = module.ziti_controller.admin_client_cert
}

# output "ziti_admin_username" {
#     sensitive = true
#     value     = "${module.ziti_controller.ziti_admin_password["admin-user"]}"
# }

# output "ziti_admin_password" {
#     sensitive = true
#     value     = "${module.ziti_controller.ziti_admin_password["admin-password"]}"
# }

# output "ctrl_plane_cas" {
#     value = "${module.ziti_controller.ctrl_plane_cas["ctrl-plane-cas.crt"]}"
# }

# resource "local_file" "ctrl_plane_cas" {
#     filename     = "../plan-20-router/.terraform/ctrl-plane-cas.crt"
#     content      = "${module.ziti_controller.ctrl_plane_cas["ctrl-plane-cas.crt"]}"
# }

# output "admin_client_cert" {
#     sensitive = true
#     value = "${module.ziti_controller.admin_client_cert["data"]["tls.crt"]}"
# }

# output "admin_client_cert_key" {
#     sensitive = true
#     value     = "${module.ziti_controller.admin_client_cert["data"]["tls.key"]}"
# }

output "ziti_controller_mgmt_external_host" {
    value = module.ziti_controller.ziti_controller_mgmt_external_host
}

output "ziti_controller_mgmt_internal_host" {
    value = module.ziti_controller.ziti_controller_mgmt_internal_host
}

output "ziti_controller_ctrl_internal_host" {
    value = module.ziti_controller.ziti_controller_ctrl_internal_host
}
