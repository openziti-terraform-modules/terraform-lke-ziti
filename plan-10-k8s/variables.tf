variable "LINODE_TOKEN" {
  description = "Your Linode API Personal Access Token. (required)"
}

variable "DO_TOKEN" {
  type        = string
  description = "Digital Ocean API token for solving ACME DNS01 challenges by managing TXT records in the cluster DNS zone."
}
variable "email" {
  description = "The email address cert-manager should submit during ACME request to Let's Encrypt for server certs. (required)"
}

variable "dns_zone" {
  description = "The domain name zone to maintain in Linode, e.g., ziti.example.com. (required)"
}

variable "label" {
  description = "The unique label to assign to this cluster."
  default     = "my-openziti-cluster"
}

variable "k8s_version" {
  description = "The Kubernetes version to use for this cluster."
  default     = "1.26" # Rancher requires <1.27
}

variable "region" {
  description = "The region where your cluster will be located."
  default     = "us-east"
}

variable "tags" {
  description = "Tags to apply to your cluster for organizational purposes."
  type        = list(string)
  default     = ["prod"]
}

variable "pools" {
  description = "The Node Pool specifications for the Kubernetes cluster."
  type = list(object({
    type  = string
    count = number
  }))
  default = [
    {
      type  = "g6-standard-1"
      count = 2
    }
  ]
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

variable "wildcard_ttl_sec" {
  description = "max seconds recursive nameservers should cache the wildcard record"
  default     = "3600"
}

variable "ziti_namespace" {
  default = "ziti"
}
