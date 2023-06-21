variable "storage_class" {
  type    = string
  default = ""
}

variable "ziti_charts" {
  type    = string
  default = ""
}

variable "container_image_repo" {
  description = "router container image repository"
  default     = "docker.io/openziti/ziti-router"
}

variable "container_image_tag" {
  description = "router container image tag"
  default     = "latest"
}

variable "container_image_pull_policy" {
  description = "router container image pull policy"
  default     = "IfNotPresent"
}
