variable "intercept_config_type_id" {
    description = "the ziti id of the intercept.v1 config type"
    type = string
}

variable "host_config_type_id" {
    description = "the ziti id of the host.v1 config type"
    type = string
}

variable "role_attributes" {
    description = "service role to assign"
    type = list
}

variable "upstream_address" {
    description = "server address that provides this service"
    type = string
}

variable "upstream_port" {
    type = number
    description = "server port that provides this service"
}

variable "intercept_address" {
    description = "advertised address used by consumers to reach this service"
    type = string
}

variable "intercept_port" {
    type = number
    description = "advertised port used by consumers to reach this service"
}

variable "transport_protocol" {
    description = "tcp | udp"
    default = "tcp"
    type = string
}

variable "name" {
    description = "name slug to uniquely identify the several resources created for this service"
    type = string
}

variable "bind_semantic" {
    description = "bind policy semantic to apply to identity and service roles"
    default = "AnyOf"
    type = string
}

variable "dial_semantic" {
    description = "dial policy semantic to apply to identity and service roles"
    default = "AnyOf"
    type = string
}

variable "bind_identity_roles" {
    description = "additional identity roles that may bind (host) this service, default is '{name}-hosts'"
    default = []
    type = list
}

variable "dial_identity_roles" {
    description = "identity roles that may dial (access) this service, default is '{name}-clients'"
    default = []
    type = list
}
