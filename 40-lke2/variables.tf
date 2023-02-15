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

variable "cluster_issuer_name" {
    description = "name of the cluster-wide certificate issuer for Let's Encrypt"
    default     = "cert-manager-global"
}

variable "cluster_issuer_server" {
    description = "The ACME server URL"
    type        = string
    default     = "https://acme-v02.api.letsencrypt.org/directory"
}
