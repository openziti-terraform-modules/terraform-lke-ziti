ctrlPlane:
  port: ${ctrl_port}
  service:
    enabled: true
    type: ClusterIP

clientApi:
  port: ${client_port}
  service:
    enabled: true
    type: ClusterIP

managementApi:
  port: ${mgmt_port}
  service:
    enabled: true
    type: ClusterIP

advertisedHost: ${ziti_domain_name}.${domain_name}

persistence:
    storageClass: linode-block-storage

clientApi:
    service:
        annotations:
            kubernetes.io/ingress.class: nginx
