ingress:
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: ${cluster_issuer}
  hosts:
    - host: ${ingress_domain_name}.${domain_name}
