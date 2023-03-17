terraform {
    required_providers {
        restapi = {
            source = "qrkourier/restapi"
            version = "~> 1.23.0"
        }
    }
}

resource "restapi_object" "ziti_router" {
    debug       = true
    provider    = restapi
    path        = "/edge-routers"
    # merge maps - last wins
    data = jsonencode(merge(
        var.default_router_properties,
        var.router_properties,
        {name=var.name}
    ))
}

resource "helm_release" "ziti_router" {
    depends_on = [restapi_object.ziti_router]
    name       = var.name
    namespace  = var.namespace
    repository = "https://openziti.github.io/helm-charts"
    chart      = var.ziti_charts != "" ? "${var.ziti_charts}/ziti-router" : "ziti-router"
    version    = "<0.3"
    wait       = false  # hooks don't run if wait=true!?
    values     = [yamlencode({
        edge = {
            advertisedHost = var.edge_advertised_host
            advertisedPort = 443
            service = {
                enabled = true
                type = "ClusterIP"
            }
            ingress = {
                enabled = true
                ingressClassName = "nginx"
                annotations = var.ingress_annotations
            }
        }
        linkListeners = {
            transport = {
                advertisedHost = var.transport_advertised_host
                advertisedPort = 443
                service = {
                    enabled = true
                    type = "ClusterIP"
                }
                ingress = {
                    enabled = true
                    ingressClassName = "nginx"
                    annotations = var.ingress_annotations
                }
            }
        }
        persistence = {
            storageClass = var.storage_class != "-" ? var.storage_class : ""
        }
        ctrl = {
            endpoint = var.ctrl_endpoint
        }
        enrollmentJwt = try(jsondecode(restapi_object.ziti_router.api_response).data.enrollmentJwt, "-")
    })]
}
