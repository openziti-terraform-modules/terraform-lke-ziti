terraform {
    required_providers {
        restapi = {
            source = "qrkourier/restapi"
            version = "~> 1.23.0"
        }
    }
}

resource "restapi_object" "edge_router_policy" {
    provider    = restapi
    path        = "/edge-router-policies"
    data        = jsonencode({
        name = var.name
        semantic = var.identity_role_semantic
        edgeRouterRoles = var.router_roles
        identityRoles = var.identity_roles
    })
}

resource "restapi_object" "service_edge_router_policy" {
    provider    = restapi
    path        = "/service-edge-router-policies"
    data        = jsonencode({
        name = var.name
        semantic = var.service_role_semantic
        edgeRouterRoles = var.router_roles
        serviceRoles = var.service_roles
    })
}
