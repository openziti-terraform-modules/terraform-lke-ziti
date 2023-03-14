terraform {
    required_providers {
        restapi     = {
            source  = "qrkourier/restapi"
            version = "~> 1.22.0"
        }
    }
}

resource "restapi_object" "intercept_config" {
    path               = "/configs"
    data               = jsonencode({
        name           = "${var.name}-intercept-config"
        configTypeId   = var.intercept_config_type_id
        data           = {
            protocols  = [var.transport_protocol]
            addresses  = [var.intercept_address]
            portRanges = [{
                low    = var.intercept_port
                high   = var.intercept_port
            }]
        }
    })
}

resource "restapi_object" "host_config" {
    path             = "/configs"
    data             = jsonencode({
        name         = "${var.name}-host-config"
        configTypeId = var.host_config_type_id
        data         = {
            protocol = var.transport_protocol
            address  = var.upstream_address
            port     = var.upstream_port
        }
    })
}

resource "restapi_object" "service" {
    depends_on             = [
        restapi_object.intercept_config,
        restapi_object.host_config
    ]
    path                   = "/services"
    data                   = jsonencode({
        name               = "${var.name}-service"
        encryptionRequired = "true"
        configs            = [
            "${jsondecode(restapi_object.intercept_config.api_response).data.id}",
            "${jsondecode(restapi_object.host_config.api_response).data.id}"
        ]
        roleAttributes = var.role_attributes
    })
}

resource "restapi_object" "bind_service_policy" {
    depends_on        = [restapi_object.service]
    path              = "/service-policies"
    data              = jsonencode({
        name          = "${var.name}-bind-policy"
        type          = "Bind"
        semantic      = var.bind_semantic
        identityRoles = var.bind_identity_roles != [] ? var.bind_identity_roles : ["#${var.name}-hosts"]
        serviceRoles  = ["@${jsondecode(restapi_object.service.api_response).data.id}"]
    })
}

resource "restapi_object" "dial_service_policy" {
    depends_on        = [restapi_object.service]
    path              = "/service-policies"
    data              = jsonencode({
        name          = "${var.name}-dial-policy"
        type          = "Dial"
        semantic      = var.dial_semantic
        identityRoles = var.dial_identity_roles != [] ? var.dial_identity_roles : ["#${var.name}-clients"]
        serviceRoles  = ["@${jsondecode(restapi_object.service.api_response).data.id}"]
    })
}
