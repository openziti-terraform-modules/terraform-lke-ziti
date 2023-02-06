***********************
Linode DNS/Domain Setup
***********************
This section is used to setup the Linode DNS options if you want to connect a custom domain and be able to do SSL for public host Kubernetes apps.

There is also configuration to setup the required A records for my domain which is a var in the TF code to the Github Pages addresses.  By doing this I can host my other github pages repo on my custom domain.

Ensure you are in the ``dns`` folder for these steps.

Linode API Token
----------------
Just as we setup before for lk3, we will need a Linode API token in order for this to work and be able to setup the resources.  You can find a how to located at https://www.linode.com/docs/guides/getting-started-with-the-linode-api/

The scopes you need to give it access to are:

.. parsed-literal::

    Domains - Read/Write
    Kubernetes - Read/Write
    IPs - Read/Write
    Linodes - Read/Write

This API token will become the ``TF_VAR_token`` mentioned in the next section.

Terraform Variables
-------------------
The first thing we need to do is setup some Terraform variables that we are going to be using.

Sensitive Variables
^^^^^^^^^^^^^^^^^^^
There are some variables throughout this setup that are sensitive and you don't want to store in your ``terraform.tfvars`` file, so for these you will do a ``export`` command to set the variables on your own shell.

1. As mentioned already in the previous step you will want to from your shell run ``export TF_VAR_token=XXX`` which is the Linode API token you already setup in the previous section.
2. The ``export TF_VAR_email=xxx@xxx.com`` needs to be ran to export the email that is associated with the domain when registered.
3. The ``export TF_VAR_nodebalancer_ip=X.X.X.X`` will be the IP of the nodebalancer that was setup in the previous kubernetes step.

Other Variables
^^^^^^^^^^^^^^^
There are a few variables in the ``dns/terraform.tfvars`` file that need to be set in order to ensure your dns/domain is setup how you want.  This section will outline those variables.

Modify these for your needs.

1. The ``domain_name`` variable is the domain name you will be setting up in linode.
2. The ``github_pages_alias`` is used for github pages custom domain and sets up the required A records for that.

Terraform Cloud Login For Remote State
--------------------------------------
Before peforming the next steps you will need to login via the cli to the terraform cloud and generate a token to use following the guide at https://developer.hashicorp.com/terraform/tutorials/cloud-get-started/cloud-login

Terraform Init & Plan
---------------------
Now that we have our variables all setup and should have Terraform installed now, we can initialize our project and run a plan to verify what it will do.

Make sure you are in the ``dns`` folder and run the following:

``terraform init`` - This will initialize everything needed for the project to run and install modules.

Once this is complete you can now run the plan command to validate you have all your vars setup and it can generate everything properly before applying it:

``terraform plan -var-file="terraform.tfvars"`` which will give a output of the information that it will deploy, validate this looks right before continuing.

Deploy DNS/Domain Terraform
---------------------------
As long as we didn't have any issues with the previous Init & Plan step we can now deploy our dns & domain changes..

Ensuring we still have our ``TF_VAR_token, TF_VAR_email, and TF_VAR_nodebalancer_ip`` exported on our shell then we can run:

``terraform apply -var-file="terraform.tfvars"`` which should ask for a yes prompt and then will deploy the cluster and will generate your kubeconfig to connect to it.

Now you should see your changes reflected in the Linode UI under domains.

Let us move on to to the ``cert-manager`` folder and steps for auto SSL certs.