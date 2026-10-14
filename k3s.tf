resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

locals {
  k3s_arch             = "amd64"
  k3s_version_url      = replace(var.k3s_version, "+", "%2B")
  k3s_images_file_name = "k3s-airgap-images-${local.k3s_arch}.tar.zst"
  k3s_artifact_port    = 8080
  k3s_token            = random_password.k3s_token.result

  # k3s defaults; referenced by the node host firewall rules.
  k3s_pod_cidr     = "10.42.0.0/16"
  k3s_service_cidr = "10.43.0.0/16"

  # Static IPs let every node know the first server's and the artifact server's
  # address at boot time, without a dependency cycle between the instances
  # (the NAT user data already depends on the private instances).
  # Host offset 10 stays clear of the four addresses AWS reserves per subnet.
  static_ip_host_offset = 10
  nat_static_ip         = cidrhost(var.public_subnet_cidr, local.static_ip_host_offset)
  k3s_artifact_url      = "http://${local.nat_static_ip}:${local.k3s_artifact_port}"

  private_instance_ips = [
    for i in range(var.private_instance_count) : cidrhost(var.private_subnet_cidr, local.static_ip_host_offset + i)
  ]

  k3s_server_ips = slice(local.private_instance_ips, 0, min(var.k3s_server_count, var.private_instance_count))
  k3s_agent_ips  = slice(local.private_instance_ips, length(local.k3s_server_ips), length(local.private_instance_ips))
  k3s_server_url = "https://${local.private_instance_ips[0]}:6443"

  # Rendered per node: the first server initialises the cluster, the other
  # servers and the agents join it.
  k3s_node_configs = [
    for i, ip in local.private_instance_ips : yamlencode(merge(
      {
        token     = local.k3s_token
        "node-ip" = ip
        # Bound pod log files under /var/log/pods.
        "kubelet-arg" = [
          "container-log-max-size=10Mi",
          "container-log-max-files=3",
        ]
      },
      { for k, v in { server = local.k3s_server_url } : k => v if i > 0 },
      { for k, v in { "tls-san" = [ip] } : k => v if i < var.k3s_server_count },
      { for k, v in { "cluster-init" = true } : k => v if i == 0 && var.k3s_server_count > 1 },
    ))
  ]
}
