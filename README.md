# Terraform LKE Setup

Builds out a Linode Kubernetes Engine cluster with 

* `ingress-nginx` w/ Nodebalancer
* `cert-manager` w/ Let's Encrypt issuer
* `trust-manager`
* `ziti-controller`
* `ziti-console`
* `ziti-router`
* `httpbin` demo API

## Requires

* `terraform`
* `kubectl`
* `helm`
* `ansible`
* `ziti`

## Recommends

* Ziti tunneler, e.g., Desktop Edge, for testing Ziti services
* `k9s`
* `curl`
* `jq`

## Delegate DNS and Sign up for Stuff

1. Delegate a DNS zone to Linode's NSs so Terraform can manage the global zone. For example, to delegate my-ziti-cluster.example.com to Linode you need to create NS records in example.com named "my-ziti-cluster". You can verify it's working by checking the NS records with `dig` or [Google DNS Toolbox](https://toolbox.googleapps.com/apps/dig/#NS/) (record type `NS`).

    ```bash
    $ dig +noall +answer my-ziti-cluster.example.com. NS
    my-ziti-cluster.example.com.    1765    IN      NS      ns5.linode.com.
    my-ziti-cluster.example.com.    1765    IN      NS      ns4.linode.com.
    my-ziti-cluster.example.com.    1765    IN      NS      ns2.linode.com.
    my-ziti-cluster.example.com.    1765    IN      NS      ns3.linode.com.
    my-ziti-cluster.example.com.    1765    IN      NS      ns1.linode.com.
    ```

1. Get a Free [Terraform Cloud](https://app.terraform.io/app) Organization and API token.
1. Configure your shell env for this TF plan.

    ```bash
    export TF_VAR_token=XXX                # TF cloud API token
    export TF_CLOUD_ORGANIZATION=XXX       # your TF cloud org
    export TF_WORKSPACE=my-ziti-workspace  # workspace for this plan's remote state
    export KUBECONFIG=./kube-config        # TF will write this file in plan dir
    ```

## Run Terraform

1. In `terraform.tfvars`, specify the Linode size and count, etc., e.g.,

    ```hcl
    label = "my-ziti-cluster"
    email = "me@example.com"
    domain_name = "my-ziti-cluster.example.com"
    region = "us-west"
    pools = [
        {
            type : "g6-standard-2"
            count : 2
        }
    ]
    ```

1. Initialize the workspace.

    ```bash
    terraform init
    ```

1. Perform a dry-run.

    ```bash
    terraform plan
    ```

1. Apply the plan.

    ```bash
    terraform apply
    ```

## Play with the Cluster and Ziti Admin

1. Test cluster connection.

    ```bash
    # KUBECONFIG=./kube-config
    kubectl cluster-info
    ```

1. Print the Ziti login credential.

    ```bash
    kubectl -n ziti-controller get secrets ziti-controller-admin-secret \
        -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}' 
    ```

    ```bash
    $ kubectl -n ziti-controller get secrets ziti-controller-admin-secret \
        -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}' 
    admin-password: Gj63NwmZUJPwXsqbkzx8eQ6cdG8YBxP7
    admin-user: admin
    ```

1. Visit the console: https://console.my-ziti-cluster.example.com
1. Check the certificate. If it's from "(STAGING) Let's Encrypt" then everything is working. If not, it's probably DNS.

    ```bash
    openssl s_client -connect ziti.my-ziti-cluster.example.com:443 </dev/null 2>/dev/null \
        | openssl x509 -noout -subject -issuer
    ```

    ```bash
    $ openssl s_client -connect ziti.my-ziti-cluster.example.com:443 </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer
    subject=CN = ziti.my-ziti-cluster.example.com
    issuer=C = US, O = (STAGING) Let's Encrypt, CN = (STAGING) Artificial Apricot R3
    ```

1. Optionally, switch to Let's Encrypt Prod issuer for a *real* certificate. Uncomment these lines in `terraform.tfvars` and run `terraform apply`. The cert rate limit is real, hence Staging.

    ```bash
    cluster_issuer_name = "cert-manager-production"
    cluster_issuer_server = "https://acme-v02.api.letsencrypt.org/directory"
    ```

1. Run `ziti` CLI remotely in the admin container. Change the command to `bash` to login interactively. Then run `zitiLogin`.

    ```bash
    kubectl --namespace ziti-controller exec \
        --stdin --tty \
        ziti-controller-6c79575bb4-lh9nt \
        --container ziti-controller-admin -- \
            bash -c '
                zitiLogin &>/dev/null; 
                ziti edge list ers --output-json' \
    | jq --slurp 
    ```

## Test Ziti Demo Service

1. Add the demo client identity to Ziti Desktop Edge. The JWT is saved in `/tmp/edge-client1.jwt`.
1. Test the demo API.

    ```bash
    curl -sSf -XPOST -d ziti=awesome http://webhook.ziti/post | jq .data
    ```

## Use the Kubernetes API over Ziti

Terraform modified your Kubeconfig to have a new Ziti context named like "ziti-lke12345-ctx" pointing to the Ziti service for the Kubernetes apiserver instead of the public Linode service. Find the name and select it with `kubectl`.

```bash
$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO         NAMESPACE
*         lke95021-ctx        lke95021            lke95021-admin   default
          ziti-lke95021-ctx   ziti-lke95021-ctx   lke95021-admin   

$ kubectl --context ziti-lke12345-ctx cluster-info
Kubernetes control plane is running at https://kubernetes.default.svc
KubeDNS is running at https://kubernetes.default.svc/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

## Start Over with Fresh Ziti

Remember to forget your identity. :wink: The edge-client1 in your tunneler that is. The console is stateless other than the remembered mgmt API URL.

```bash
rm /tmp/webhook-server1.json  # forget the demo API server's identity too
terraform taint helm_release.ziti_controller  # replace controller release
terraform taint null_resource.service1_ansible_playbook  # re-run playbooks
terraform taint null_resource.router1_ansible_playbook
helm -n ziti-router1 uninstall ziti-router1  # uninstall releases installed by ansible
helm -n ziti-service1 uninstall webhook-server1
terraform apply
```
