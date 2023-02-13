ingress:
  ingressClassName: nginx
  annotations:
    cert-manager.io/cluster-issuer: ${cluster_issuer}
  hosts:
    - host: ${ziti_domain_name}.${domain_name}
  tls:
  - hosts:
    - ${ziti_domain_name}.${domain_name}
    secretName: ${console_release}-tls-secret

settings:
  edgeControllers:
    - name: Ziti Edge Mgmt API
      url: https://${controller_release}-mgmt.${controller_namespace}.svc:${edge_mgmt_port}
      default: true
