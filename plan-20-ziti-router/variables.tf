variable "router1_name" {
    description = "Helm release name for router1"
    default = "router1"
}

variable "storage_class" {
    description = "Storage class to use for persistent volumes"
    default = ""
}

variable "service1_namespace" {
    description = "namespace to place service1"
    default = "default"
}

variable "ziti_charts" {
    description = "Filesystem path to source OpenZiti Helm Charts instead of Helm repo"
    type = string
    default = ""
}

variable "container_image_repository" {
    type        = string
    description = "The ziti-router container image repository"
    default     = "docker.io/openziti/ziti-router"
}

variable "container_image_tag" {
    type        = string
    description = "The ziti-router container image tag"
    default     = "latest"
}

variable "container_image_pull_policy" {
    type        = string
    description = "The ziti-router container image pull policy"
    default     = "IfNotPresent"
}