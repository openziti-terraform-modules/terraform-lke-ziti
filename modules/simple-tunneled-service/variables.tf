variable "intercept_config_type_id" {
    description = "the ziti id of the intercept.v1 config type"
}

variable "host_config_type_id" {
    description = "the ziti id of the host.v1 config type"
}

variable "role_attribute" {
    # type = list(string)  # TODO: iterate over members as JSON in template
    description = "service role to assign"
}

variable "upstream_address" {
    description = "server address that provides this service"
}

variable "upstream_port" {
    type = number
    description = "server port that provides this service"
}

variable "intercept_address" {
    description = "advertised address used by consumers to reach this service"
}

variable "intercept_port" {
    type = number
    description = "advertised port used by consumers to reach this service"
}

variable "transport_protocol" {
    description = "tcp | udp"
    default = "tcp"
}

variable "name" {
    description = "name slug to uniquely identify the several resources created for this service"
}