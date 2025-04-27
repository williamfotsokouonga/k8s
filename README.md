# Kubernetes K8s on AWS with Terraform
## Install Terraform

1 - Install brew 
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

2 - Install Terraform
  brew tap hashicorp/tap
  brew install hashicorp/tap/terraform

3 - Control Terraform version
  terraform --version   [1.11.4]
  GitHub : https://github.com/hashicorp/terraform
  Web :    https://developer.hashicorp.com/terraform/install
  
## CONFIGURATION KEY AWS
## CREATE K8S CLUSTER 
- 3 EC2 Masters
- 3 EC2 Workers
