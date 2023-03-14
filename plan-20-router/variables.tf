variable "router1_name" {
    description = "Helm release name for router1"
    default = "router1"
}

variable "service1_namespace" {
    description = "namespace to place service1"
    default = "default"
}

variable "ziti_charts" {
    description = "Filesystem path to source OpenZiti Helm Charts instead of Helm repo"
    type = string
    default = ""
}
