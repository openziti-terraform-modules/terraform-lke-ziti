controller:
  service:
    annotations:
tcp:
  ${client_port}: "${controller_namespace}/${client_svc}:${client_port}"
