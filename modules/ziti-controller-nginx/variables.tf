variable "ziti_controller_release" {
    description = "name of Helm release for OpenZiti Controller on which to build conventional resource names"
}

variable "ziti_namespace" {
    default = "ziti"
    description = "K8s namespace where OpenZiti Controller is installed"
}

variable "ziti_charts" {
    description = "Filesystem path to source OpenZiti Helm Charts instead of Helm repo"
    type = string
    default = ""
}

variable "dns_zone" {
    description = "The domain name zone to maintain in Linode, e.g., ziti.example.com. (required)"
}

variable "ctrl_domain_name" {
    description = "The subdomain name to use for Ziti router Ctrl Plane"
    default     = "ctrl"     # wildcard DNS record resolves all names to the Nodebalancer
}

variable "ctrl_port" {
    description = "Ziti ctrl plane port for routers that's provided by the Ziti controller"
    default     = 443
}

variable "client_domain_name" {
    description = "The subdomain name to use for Ziti Edge Client API"
    default     = "client"   # wildcard DNS record resolves all names to the Nodebalancer
}

variable "client_port" {
    description = "Ziti Edge client API port for SDK enrollment, auth, discovery"
    default     = 443
}

variable "mgmt_domain_name" {
    description = "The subdomain name to use for Ziti Edge Management API. This is identical to Client API if the Management API cluster service is disabled."
    default = "management"
}

variable "mgmt_port" {
    description = "Ziti Edge mgmt API port used by ziti CLI and console"
    default     = 443
}

variable "install" {
    description = "install OpenZiti Controller Helm Chart unless false"
    default     = true
}

variable "mgmt_dns_san" {
    description = "DNS Subject Alternative Name for the Managment API facilitates exposing this service with an OpenZiti intercept address."
    default = "mgmt.ziti"
}

variable "storage_class" {
    description = "storage class to fulfill this controller's persistent volume claim"
    default = "-"
}

variable "ingress_annotations" {
    description = "annotations on the router's ingress resource to trigger ingress-nginx controller"
    default = {
        "kubernetes.io/ingress.allow-http" = "false"
        "nginx.ingress.kubernetes.io/ssl-passthrough" = "true"
        "nginx.ingress.kubernetes.io/secure-backends" = "true"
    }
}

variable "prometheus_enabled" {
    description = "enable Prometheus metrics collection"
    default = "true"
    type = string
}

variable "image_repo" {
    description = "debug value for alternative container image repo"
    default = "openziti/ziti-controller"
}

variable "admin_image_repo" {
    description = "debug value for alternative admin container image repo"
    default = "openziti/ziti-cli"
}

variable "image_tag" {
    description = "debug value for container image tag"
    default = ""
}

variable "values" {
    description = "additional Helm chart values override any other values"
    default = {}
}