# Basic example

A NAT/bastion instance and three private EC2 instances that form a k3s cluster
installed with the air-gap method (artifacts are served by the bastion).

```bash
terraform init
terraform apply
terraform output -raw private_key_save_command | sh

# wait a few minutes for bootstrap, then:
eval "$(terraform output -raw k3s_kubeconfig_command)"
terraform output -raw k3s_api_tunnel_command   # run in a separate shell
KUBECONFIG=./kubeconfig.yaml kubectl get nodes
```
