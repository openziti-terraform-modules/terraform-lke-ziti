# Terraform LKE Setup
Builds out a cluster on Linode for kubernetes also known as LKE on Linode.

**Ensure you have updated the terraform.tfvars appropriately to match the values you want to use.**

**Ensure you have the `export TF_VAR_token=XXX` var setup before running any of the following commands and ensure you have Terraform installed.**

`terraform init` - To setup the terraform initially

`terraform plan -var-file="terraform.tfvars"` - To validate before deploying what will be deployed.

`terraform apply -var-file="terraform.tfvars"` - To apply the changes/deploy cluster.

After deploy we now need to generate our kubernetes config and tell kubectl to use it for connecting:

```
export KUBE_VAR=`terraform output kubeconfig` && echo $KUBE_VAR | base64 -di > lke-cluster-config.yaml

```

Then we can run the following to tell kubectl to use it:

```
export KUBECONFIG=$(pwd)/lke-cluster-config.yaml
```

Now `kubectl cluster-info` should work.

```bash
$ kubectl -n ziti-controller get secrets ziti-controller-release-admin-secret \
    -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}' 
admin-password: Gj63NwmZUJPwXsqbkzx8eQ6cdG8YBxP7
admin-user: admin
```
