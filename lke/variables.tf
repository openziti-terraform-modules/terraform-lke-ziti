variable "token" {
    description = "Your Linode API Personal Access Token. (required)"
}

variable "k8s_version" {
    description = "The Kubernetes version to use for this cluster. (required)"
    default = "1.23"
}

variable "label" {
    description = "The unique label to assign to this cluster. (required)"
    default = "devops-with-brian"
}

variable "region" {
    description = "The region where your cluster will be located. (required)"
    default = "us-east"
}

variable "tags" {
    description = "Tags to apply to your cluster for organizational purposes. (optional)"
    type = list(string)
    default = ["prod"]
}

variable "pools" {
    description = "The Node Pool specifications for the Kubernetes cluster. (required)"
    type = list(object({
        type = string
        count = number
    }))
    default = [
        {
            type = "g6-standard-1"
            count = 3
        }
    ]
}

variable "email" {
    description = "The email address cert-manager should submit during ACME request to Let's Encrypt for server certs."
}

variable "domain_name" {
    description = "The domain name zone to maintain in Linode"
}

variable "ingress_domain_name" {
    description = "The subdomain name to use for ingress_domain_name record"
    default     = "*"  # wildcard DNS record resolves all names to the Nodebalancer
}

variable "ziti_domain_name" {
    description = "The subdomain name to use for Ziti console"
    default     = "ziti"  # wildcard DNS record resolves all names to the Nodebalancer
}

variable "cluster_issuer" {
    description = "name of the cluster-wide certificate issuer for Let's Encrypt"
    default     = "cert-manager-global"
}

variable "ziti_ctrl_port" {
    description = "Ziti ctrl plane port for routers that's provided by the Ziti controller"
    default     = 6262
}

variable "ziti_client_port" {
    description = "Ziti Edge client API port for SDK enrollment, auth, discovery"
    default     = 1280
}

variable "ziti_client_svc" {
    description = "Cluster service name of Ziti Edge client API"
    default     = "ziti-controller-release-client"
}

variable "ziti_mgmt_port" {
    description = "Ziti Edge mgmt API port for ziti CLI and console"
    default     = 1281
}

variable "ziti_controller_namespace" {
    description = "Ziti Controller namespace"
    default     = "ziti-controller"
}
