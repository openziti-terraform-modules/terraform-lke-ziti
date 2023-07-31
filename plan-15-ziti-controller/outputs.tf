
output "ziti_admin_password" {
  sensitive = true
  value     = module.ziti_controller.ziti_admin_password
}

output "ctrl_plane_cas" {
  value = nonsensitive(module.ziti_controller.ctrl_plane_cas)
}

output "ctrl_plane_cas_configmap" {
  value = module.ziti_controller.ctrl_plane_cas_configmap
}

output "admin_client_cert" {
  sensitive = true
  value     = module.ziti_controller.admin_client_cert
}

output "ziti_controller_mgmt_external_host" {
  value = nonsensitive(module.ziti_controller.ziti_controller_mgmt_external_host)
}

output "ziti_controller_mgmt_internal_host" {
  value = nonsensitive(module.ziti_controller.ziti_controller_mgmt_internal_host)
}

output "ziti_controller_ctrl_internal_host" {
  value = nonsensitive(module.ziti_controller.ziti_controller_ctrl_internal_host)
}
