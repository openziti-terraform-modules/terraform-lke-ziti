variable "router_role" {
    description = "the edge router role that represents public routers that should advertise availability to edge clients for edge connections"
}

variable "identity_role" {
    description = "Group of OpenZiti Identities that should use this public router policy for outgoing Edge connections."
    default = "all"
}

variable "service_role" {
    description = "Group of OpenZiti Services that should use this public router policy for incoming Edge connections."
    default = "all"
}
