variable "token" {
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

variable "console_domain_name" {
    description = "The subdomain name to use for Ziti console"
    default     = "ziti"  # wildcard DNS record resolves all names to the Nodebalancer
}

variable "ctrl_domain_name" {
    description = "The subdomain name to use for Ziti router ctrl plane"
    default     = "ctrl"  # wildcard DNS record resolves all names to the Nodebalancer
}

variable "client_domain_name" {
    description = "The subdomain name to use for Ziti Edge client API"
    default     = "edge"  # wildcard DNS record resolves all names to the Nodebalancer
}

variable "ziti_console_release" {
    default = "ziti-console"
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
    description = "Ziti Edge mgmt API port for ziti CLI and console"
    default     = 443
}

variable "ziti_controller_namespace" {
    description = "Ziti Controller namespace"
    default     = "ziti-controller"
}

variable "wildcard_ttl_sec" {
    description = "max seconds recursive nameservers should cache the wildcard record"
    default = "3600"
}

variable "router1_namespace" {
    description = "namespace to create for router1"
    default = "ziti-router1"
}

variable "router1_release" {
    description = "Helm release name for router1"
    default = "ziti-router1"
}

variable "router1_transport_domain_name" {
    description = "DNS name for the transport service router1 provides to other routers"
    default = "router1-transport"
}

variable "service1_namespace" {
    description = "namespace to create for service1"
    default = "ziti-service1"
}

variable "service1_release" {
    description = "Helm release name for service1"
    default = "webhook-server1"
}
variable "router1_edge_domain_name" {
    description = "DNS name for the edge service router1 provides to edge SDK clients"
    default = "router1-edge"
}
