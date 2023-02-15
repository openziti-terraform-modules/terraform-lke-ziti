output "kubeconfig" {
   value = linode_lke_cluster.linode_lke.kubeconfig
   sensitive = true
}

output "api_endpoints" {
   value = linode_lke_cluster.linode_lke.api_endpoints
}

output "status" {
   value = linode_lke_cluster.linode_lke.status
}

output "id" {
   value = linode_lke_cluster.linode_lke.id
}

output "pool" {
   value = linode_lke_cluster.linode_lke.pool
}

resource "local_sensitive_file" "kubeconfig" {
  depends_on   = [linode_lke_cluster.linode_lke]
  filename     = "./kube-config"
  content      = base64decode(linode_lke_cluster.linode_lke.kubeconfig)
  file_permission = 0600
}

output "ingress_nginx_values" {
   value = data.template_file.ingress_nginx_values.rendered
}

output "ziti_controller_values" {
   value = data.template_file.ziti_controller_values.rendered
}

output "ziti_router_values" {
   value = data.template_file.ziti_router_values.rendered
}

resource "local_file" "ziti_router_values" {
  filename     = "./outputs-values-ziti-router.yaml"
  content      = data.template_file.ziti_router_values.rendered
  file_permission = 0600
}

output "ziti_console_values" {
   value = data.template_file.ziti_console_values.rendered
}

output "ctrl_domain_name" {
  value = var.ctrl_domain_name
}

output "ctrl_port" {
  value = var.ctrl_port
}

output "domain_name" {
   value = var.domain_name
}

output "email" {
   value = var.email
}

output "tags" {
   value = var.tags
}

output "ziti_controller_mgmt" {
   value = "https://${helm_release.ziti_controller.name}-mgmt.${helm_release.ziti_controller.namespace}.svc:${var.mgmt_port}"
}