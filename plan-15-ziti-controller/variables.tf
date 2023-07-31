
variable "ziti_charts" {
  description = "Filesystem path to source OpenZiti Helm Charts instead of Helm repo"
  type        = string
  default     = ""
}

variable "ziti_controller_release" {
  description = "Helm release name for ziti-controller"
  default     = "ziti-controller"
}

variable "ziti_console_release" {
  default     = "ziti-console"
  description = "Name of Helm release for OpenZiti Console"
}

variable "storage_class" {
  description = "Storage class to use for persistent volumes"
  default     = ""
}

variable "container_image_repository" {
  type        = string
  description = "The ziti-controller container image repository"
  default     = "docker.io/openziti/ziti-controller"
}

variable "container_image_tag" {
  type        = string
  description = "The ziti-controller container image tag"
  default     = ""
}

variable "container_image_pull_policy" {
  type        = string
  description = "The ziti-controller container image pull policy"
  default     = "IfNotPresent"
}

variable "tf_cloud_remote_state_organization" {
  type    = string
  default = ""
}

variable "tf_cloud_remote_state_k8s_workspace" {
	type    = string
	default = ""
}