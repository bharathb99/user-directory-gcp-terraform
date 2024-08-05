
#### Terraform commands

terraform init: Initialize a Terraform working directory containing Terraform configuration files.

terraform plan: Generate an execution plan showing what Terraform will do when you apply the configuration.

terraform apply: Apply the changes required to reach the desired state of the configuration.

terraform destroy: Destroy the Terraform-managed infrastructure.

#### GCLOUD SETUP
Initialize gcloud:
Run gcloud init to create a new configuration and add a new project.
https://cloud.google.com/sdk/docs/install

Verify Project:
Go to the Google Cloud Console to verify that the project is created.

Login:
Authenticate with your Google account using:

gcloud auth login
gcloud auth application-default login

Set Project:
Set the project for gcloud:

gcloud config set project [PROJECT_ID]

## Define Your Resources
Initialize Terraform:
    terraform init 

to initialize the working directory containing Terraform configuration files.

Plan Terraform Execution:
    terraform plan

Apply Terraform Configuration:
    terraform apply

All the defined resources will be created in the Google Cloud Platform.


To create resources from the command line, you can use the following:

## Plan Resources:
terraform plan -var "webapp_subnet_cidr=10.1.2.0/24" -var "db_subnet_cidr=10.2.2.0/24" -var='vpc_name=["cloud-vpc1", "cloud-vpc2"]' -var "custom_image=URL_TO_CUSTOM_IMAGE"

## Apply Resources:
terraform apply -var "webapp_subnet_cidr=10.1.2.0/24" -var "db_subnet_cidr=10.2.2.0/24" -var='vpc_name=["cloud-vpc1", "cloud-vpc2"]' -var "custom_image=URL_TO_CUSTOM_IMAGE"

These commands will create resources with the specified VPC names, CIDR ranges, Custom image in the Google Cloud Platform. Adjust the variable values as needed.