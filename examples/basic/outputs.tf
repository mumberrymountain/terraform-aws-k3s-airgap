output "key_pair_name" {
  value = module.airgap.key_pair_name
}

output "private_key_pem" {
  description = "Private key PEM for the module-created key pair. Null when an existing key_name was provided."
  value       = module.airgap.private_key_pem
  sensitive   = true
}

output "private_key_save_command" {
  value = module.airgap.private_key_save_command
}

output "ssh_via_nat_example" {
  value = module.airgap.ssh_via_nat_example
}

output "scp_via_nat_example" {
  value = module.airgap.scp_via_nat_example
}

output "vpc_id" {
  value = module.airgap.vpc_id
}

output "nat_public_ip" {
  value = module.airgap.nat_public_ip
}

output "private_instance_private_ips" {
  value = module.airgap.private_instance_private_ips
}

output "ssh_example" {
  value = module.airgap.ssh_example
}

output "scp_example" {
  value = module.airgap.scp_example
}

output "k3s_server_private_ips" {
  value = module.airgap.k3s_server_private_ips
}

output "k3s_agent_private_ips" {
  value = module.airgap.k3s_agent_private_ips
}

output "k3s_kubeconfig_command" {
  value = module.airgap.k3s_kubeconfig_command
}

output "k3s_api_tunnel_command" {
  value = module.airgap.k3s_api_tunnel_command
}
