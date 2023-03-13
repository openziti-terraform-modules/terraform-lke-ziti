terraform {
    required_providers {
        restapi = {
            source = "qrkourier/restapi"
            version = "~> 1.22.0"
        }
    }
}


resource "restapi_object" "edge_router_policy" {
    provider    = restapi
    path        = "/edge-router-policies"
    data = <<-EOF
        {
            "name": "public-routers",
            "semantic": "AnyOf",
            "edgeRouterRoles": [
                "#${var.router_role}"
            ],
            "identityRoles": [
                "#${var.identity_role}"
            ]
        }
    EOF
}

resource "restapi_object" "service_edge_router_policy" {
    provider    = restapi
    path        = "/service-edge-router-policies"
    data = <<-EOF
        {
            "name": "public-routers",
            "semantic": "AnyOf",
            "edgeRouterRoles": [
                "#${var.router_role}"
            ],
            "serviceRoles": [
                "#${var.service_role}"
            ]
        }
    EOF
}
