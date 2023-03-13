output "id" {
    value = jsondecode(restapi_object.ziti_router.api_response).data.id
}
