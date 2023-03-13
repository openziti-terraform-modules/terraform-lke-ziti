variable "router1_release" {
    description = "Helm release name for router1"
    default = "ziti-router1"
}

variable "router1_transport_domain_name" {
    description = "DNS name for the transport service router1 provides to other routers"
    default = "router1-transport"
}

variable "router1_edge_domain_name" {
    description = "DNS name for the edge service router1 provides to edge SDK clients"
    default = "router1-edge"
}

variable "service1_namespace" {
    description = "namespace to place service1"
    default = "default"
}

variable "service1_release" {
    description = "Helm release name for service1"
    default = "webhook-server1"
}

variable "ziti_charts" {
    description = "Filesystem path to source OpenZiti Helm Charts instead of Helm repo"
    type = string
    default = ""
}
