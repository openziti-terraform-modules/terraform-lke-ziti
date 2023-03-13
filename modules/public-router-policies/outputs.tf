output "erp_id" {
    value = jsondecode(restapi_object.edge_router_policy.api_response).data.id
}

output "serp_id" {
    value = jsondecode(restapi_object.service_edge_router_policy.api_response).data.id
}
