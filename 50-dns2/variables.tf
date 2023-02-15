variable "token" {
    description = "Your Linode API Personal Access Token. (required)"
}

variable "nodebalancer_ip" {
    description = "IPv4 address of the nodebalancer created by the ingress-nginx chart in the LKE plan"  
}

variable "wildcard_ttl_sec" {
    description = "max seconds recursive nameservers should cache the wildcard record"
    default = "21600"
}

variable "tags" {
    description = "Tags to apply to your cluster for organizational purposes. (optional)"
    type = list(string)
    default = ["prod"]
}

variable "email" {
    description = "The email address cert-manager should submit during ACME request to Let's Encrypt for server certs."
}

variable "domain_name" {
    description = "The domain name zone to maintain in Linode"
}

