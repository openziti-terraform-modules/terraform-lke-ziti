terraform {
    required_providers {
        restapi = {
            source = "qrkourier/restapi"
            version = "~> 1.22.0"
        }
    }
}

resource "restapi_object" "ziti_router" {
    debug       = true
    provider    = restapi
    path        = "/edge-routers"
    data = jsonencode(var.router_properties)
}

data "template_file" "ziti_router_values" {
    template = yamlencode({
        edge = {
            advertisedHost = var.edge_advertised_host
            advertisedPort = 443
            service = {
                enabled = "true"
                type = "ClusterIP"
                ingress = {
                    enabled = "true"
                    ingressClassName = "nginx"
                    annotations = {
                        "kubernetes.io/ingress.allow-http" = "false"
                        "nginx.ingress.kubernetes.io/ssl-passthrough" = "true"
                        "nginx.ingress.kubernetes.io/secure-backends" = "true"
                    }
                }
            }
        }
        linkListeners = {
            transport = {
                advertisedHost = var.transport_advertised_host
                advertisedPort = 443
                service = {
                    enabled = "true"
                    type = "ClusterIP"
                }
                ingress = {
                    enabled = "true"
                    ingressClassName = "nginx"
                    annotations = {
                        "kubernetes.io/ingress.allow-http" = "false"
                        "nginx.ingress.kubernetes.io/ssl-passthrough" = "true"
                        "nginx.ingress.kubernetes.io/secure-backends" = "true"
                    }
                }
            }
        }
        persistence = {
            storageClass = try(var.storage_class, "")
        }
        ctrl = {
            endpoint = var.ctrl_endpoint
        }
        enrollmentJwt = try(jsondecode(restapi_object.ziti_router.api_response).data.enrollmentJwt, "dummystring")
    })
}

resource "helm_release" "ziti_router" {
    depends_on = [restapi_object.ziti_router]
    name       = var.name
    namespace  = var.namespace
    repository = "https://openziti.github.io/helm-charts"
    chart      = var.ziti_charts != "" ? "${var.ziti_charts}/ziti-router" : "ziti-router"
    version    = "<0.3"
    wait       = false  # hooks don't run if wait=true!?
    values     = [data.template_file.ziti_router_values.rendered]
}
