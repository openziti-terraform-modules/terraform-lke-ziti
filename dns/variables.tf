variable "token" {
    description = "Your Linode API Personal Access Token. (required)"
}

variable "nodebalancer_ip" {
    description = "IPv4 address of the nodebalancer created by the ingress-nginx chart in the LKE plan"  
}
