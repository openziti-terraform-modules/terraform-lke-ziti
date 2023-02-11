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

resource "local_file" "kubeconfig" {
  depends_on   = [linode_lke_cluster.linode_lke]
  filename     = "kube-config"
  content      = base64decode(linode_lke_cluster.linode_lke.kubeconfig)
}

output "nodebalancer_id" {
   value = linode_nodebalancer.ingress_nginx_nodebalancer.id
}