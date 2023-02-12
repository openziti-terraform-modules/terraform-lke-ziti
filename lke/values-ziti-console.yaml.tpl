ingress:
  ingressClassName: nginx
  annotations:
    cert-manager.io/cluster-issuer: ${cluster_issuer}
  hosts:
    - host: ${ziti_domain_name}.${domain_name}
settings:
  edgeControllers:
    - name: Ziti Edge Mgmt API
      url: https://${controller_release}-mgmt.${controller_namespace}.svc:${edge_mgmt_port}
      default: true
