ziti edge create identity device webhook-client1 \
    --jwt-output-file /tmp/webhook-client1.jwt --role-attributes webhook-clients

ziti edge create identity device webhook-server1 \
    --jwt-output-file /tmp/webhook-server1.jwt --role-attributes webhook-servers

ziti edge create config webhook-intercept-config intercept.v1 \
    '{"protocols":["tcp"],"addresses":["webhook.ziti"], "portRanges":[{"low":80, "high":80}]}'

ziti edge create config webhook-host-config host.v1 \
    '{"protocol":"tcp", "address":"httpbin","port":8080}'

ziti edge create service webhook-service1 --configs webhook-intercept-config,webhook-host-config

ziti edge create service-policy webhook-bind-policy Bind \
    --service-roles '@webhook-service1' --identity-roles '#webhook-servers'

ziti edge create service-policy webhook-dial-policy Dial \
    --service-roles '@webhook-service1' --identity-roles '#webhook-clients'

ziti edge create edge-router-policy default \
    --edge-router-roles '#default' --identity-roles '#all'

ziti edge create service-edge-router-policy default \
    --edge-router-roles '#default' --service-roles '#all'

ziti edge enroll /tmp/webhook-server1.jwt


