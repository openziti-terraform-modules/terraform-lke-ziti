variable "tf_org" {
    description = "The name of the Terraform cloud organization where remote state workspaces for this project are maintained (required)."
}

variable "tf_workspace_zitik8s" {
    description = "The name of the Terraform cloud workspace that holds the remote state for the main LKE+Ziti plan (required)."
}
