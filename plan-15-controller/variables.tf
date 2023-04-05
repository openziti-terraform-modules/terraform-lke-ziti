
variable "ziti_charts" {
    description = "Filesystem path to source OpenZiti Helm Charts instead of Helm repo"
    type = string
    default = ""
}

variable "ziti_controller_release" {
    description = "Helm release name for ziti-controller"
    default = "ziti-controller"
}

variable "ziti_console_release" {
    default = "ziti-console"
    description = "Name of Helm release for OpenZiti Console"
}

variable "storage_class" {
    description = "Storage class to use for persistent volumes"
    default = ""
}
