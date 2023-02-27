# Terraform LKE Setup

Builds out a Linode Kubernetes Engine cluster with 

* ingress-nginx w/ Nodebalancer
* cert-manager w/ Let's Encrypt issuer
* trust-manager
* ziti-controller
* ziti-console
* ziti-router
* httpbin demo API

## Init

1. Delegate a DNS zone to Linode's NSs, e.g. ns1.linode.com. For example, to delegate my-ziti-cluster.example.com to Linode you need to create NS records in example.com named "my-ziti-cluster". You can verify it's working by checking the NS records with `dig` or [Google DNS Toolbox](https://toolbox.googleapps.com/apps/dig/#NS/) (record type `NS`).

    ```bash
    $ dig +noall +answer my-ziti-cluster.example.com. NS
    my-ziti-cluster.example.com.    1765    IN      NS      ns5.linode.com.
    my-ziti-cluster.example.com.    1765    IN      NS      ns4.linode.com.
    my-ziti-cluster.example.com.    1765    IN      NS      ns2.linode.com.
    my-ziti-cluster.example.com.    1765    IN      NS      ns3.linode.com.
    my-ziti-cluster.example.com.    1765    IN      NS      ns1.linode.com.
    ```

1. In `terraform.tfvars`, specify the Linode size and count, etc., e.g.,

    ```json
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

1. Get a Free [Terraform Cloud](https://app.terraform.io/app) Organization and API token.
1. Configure your shell env for this TF plan.

    ```bash
    export TF_VAR_token=XXX                # TF cloud API token
    export TF_CLOUD_ORGANIZATION=XXX       # your TF cloud org
    export TF_WORKSPACE=my-ziti-workspace  # workspace for this plan's remote state
    export KUBECONFIG=./kube-config        # TF will write this file in plan dir
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

1. Test cluster connection.

    ```bash
    kubectl cluster-info
    ```

1. Print the Ziti login credential.

    ```bash
    kubectl -n ziti-controller get secrets ziti-controller-secret \
        -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}' 
    ```

    ```bash
    $ kubectl -n ziti-controller get secrets ziti-controller-release-admin-secret \
        -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}' 
    admin-password: Gj63NwmZUJPwXsqbkzx8eQ6cdG8YBxP7
    admin-user: admin
    ```

1. Visit the console: https://ziti.my-ziti-cluster.example.com

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

1. Optionally, switch to Let's Encrypt Prod issuer for a *real* certificate. Uncomment these lines in `terraform.tfvars` and run `terraform apply`.

    ```bash
    cluster_issuer_name = "cert-manager-production"
    cluster_issuer_server = "https://acme-v02.api.letsencrypt.org/directory"
    ```

