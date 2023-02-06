# Linode Terraform DNS/Domain
Builds out a domain and dns records for use with lke ingress.  This also has options setup for the github pages custom domain setup, you can comment those sections out if you don't want to use them.

**Ensure you have updated the terraform.tfvars appropriately to match the values you want to use.**

**Ensure you have the `export TF_VAR_email=XXX@XXX.com` var setup before running any of the following commands and ensure you have Terraform installed.  You can also just set this in the terraform.tfvars**

**Ensure you have the `export TF_VAR_nodebalancer_ip=X.X.X.X` var setup before running any of the following commands and ensure you have Terraform installed.  You can also just set this in the terraform.tfvars**

**Ensure you have the `export TF_VAR_token=XXX` var setup before running any of the following commands and ensure you have Terraform installed.**

`terraform init` - To setup the terraform initially

`terraform plan -var-file="terraform.tfvars"` - To validate before deploying what will be deployed.

`terraform apply -var-file="terraform.tfvars"` - To apply the changes/deploy cluster.