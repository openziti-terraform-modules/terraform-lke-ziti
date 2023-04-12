variable "domain_name" {
    description = "The domain name zone to maintain in Linode, e.g., ziti.example.com. Default is to inherit and use the same name as the LKE plan."
    default = null
}

variable "router_name" {
    description = "Helm release name for router1"
    default = "router1"
}

variable "service1_namespace" {
    description = "namespace to place service1"
    default = "default"
}

variable "service_name" {
    description = "Helm release name for service1"
    default = "testapi1"
}

variable "ziti_charts" {
    description = "Filesystem path to source OpenZiti Helm Charts instead of Helm repo"
    type = string
    default = ""
}
