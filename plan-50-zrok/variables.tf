variable "container_image_repository" {
    type        = string
    description = "The zrok container image repository"
    default     = "openziti/zrok"
}

variable "container_image_tag" {
    type        = string
    description = "The zrok container image tag"
    default     = "latest"
}

variable "container_image_pull_policy" {
    type        = string
    description = "The zrok container image pull policy"
    default     = "IfNotPresent"
}

variable "controller_dns_name" {
    type        = string
    description = "The DNS name of the zrok controller"
    default     = "zrok"
}

variable "ziti_charts" {
    type        = string
    description = "alternative file path to ziti charts"
    default     = ""
}

variable "storage_class" {
    type        = string
    description = "The storage class to use for persistent volumes"
    default     = ""
}