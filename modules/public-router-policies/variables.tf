variable "router_roles" {
    description = "the edge router roles that represents public routers that should advertise availability to edge clients for edge connections"
    type = list
    default = ["#public-routers"]
}

variable "identity_roles" {
    description = "the identity roles that should use this public router policy"
    default = ["#all"]
}

variable "service_roles" {
    description = "the service roles that should use this public router policy"
    default = ["#all"]
}

variable "name" {
    description = "name of the router policy and service router policy to create"
    default = "public-routers"
}

variable "identity_role_semantic" {
    description = "policy semantic to apply to identity roles"
    default = "AnyOf"
}

variable "service_role_semantic" {
    description = "policy semantic to apply to service roles"
    default = "AnyOf"
}
