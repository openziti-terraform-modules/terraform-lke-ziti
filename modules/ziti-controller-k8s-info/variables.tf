variable "ziti_controller_release" {
    default = "ziti-controller"
    description = "name of Helm release for OpenZiti Controller on which to build conventional resource names"
}

variable "ziti_namespace" {
    default = "ziti"
    description = "K8s namespace where OpenZiti Controller is installed"
}

# variable "mgmt_port" {
#     description = "Ziti Edge mgmt API port used by ziti CLI and console"
#     default     = 443
# }
