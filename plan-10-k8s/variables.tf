variable "LINODE_TOKEN" {
    description = "Your Linode API Personal Access Token. (required)"
}

variable "email" {
    description = "The email address cert-manager should submit during ACME request to Let's Encrypt for server certs. (required)"
}

variable "domain_name" {
    description = "The domain name zone to maintain in Linode, e.g., ziti.example.com. (required)"
}

variable "label" {
    description = "The unique label to assign to this cluster."
    default = "my-openziti-cluster"
}

variable "k8s_version" {
    description = "The Kubernetes version to use for this cluster."
    default = "1.25"
}

variable "region" {
    description = "The region where your cluster will be located."
    default = "us-east"
}

variable "tags" {
    description = "Tags to apply to your cluster for organizational purposes."
    type = list(string)
    default = ["prod"]
}

variable "pools" {
    description = "The Node Pool specifications for the Kubernetes cluster."
    type = list(object({
        type = string
        count = number
    }))
    default = [
        {
            type = "g6-standard-1"
            count = 2
        }
    ]
}

variable "ziti_charts" {
    description = "Filesystem path to source OpenZiti Helm Charts instead of Helm repo"
    type = string
    default = ""
}

variable "console_domain_name" {
    description = "The subdomain name to use for Ziti console"
    default     = "console"  # wildcard DNS record resolves all names to the Nodebalancer
}

variable "ctrl_domain_name" {
    description = "The subdomain name to use for Ziti router Ctrl Plane"
    default     = "ctrl"     # wildcard DNS record resolves all names to the Nodebalancer
}

variable "client_domain_name" {
    description = "The subdomain name to use for Ziti Edge Client API"
    default     = "client"   # wildcard DNS record resolves all names to the Nodebalancer
}

variable "mgmt_domain_name" {
    description = "The subdomain name to use for Ziti Edge Management API"
    default     = "management"   # wildcard DNS record resolves all names to the Nodebalancer
}

variable "ziti_console_release" {
    default = "ziti-console"
    description = "Name of Helm release for OpenZiti Console"
}

variable "cluster_issuer_name" {
    description = "name of the cluster-wide certificate issuer for Let's Encrypt"
    default     = "cert-manager-staging"
}

variable "cluster_issuer_server" {
    description = "The ACME server URL"
    type        = string
    default     = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

variable "ctrl_port" {
    description = "Ziti ctrl plane port for routers that's provided by the Ziti controller"
    default     = 443
}

variable "client_port" {
    description = "Ziti Edge client API port for SDK enrollment, auth, discovery"
    default     = 443
}

variable "mgmt_port" {
    description = "Ziti Edge mgmt API port used by ziti CLI and console"
    default     = 443
}

variable "ziti_namespace" {
    description = "Ziti Namespace"
    default     = "ziti"
}

variable "wildcard_ttl_sec" {
    description = "max seconds recursive nameservers should cache the wildcard record"
    default = "3600"
}
