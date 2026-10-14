data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu_24" {
  count = var.private_instance_ami == null ? 1 : 0

  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "amazon_linux_2023" {
  count = var.nat_instance_ami == null ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  availability_zone = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])

  private_instance_ami_id = coalesce(var.private_instance_ami, try(data.aws_ami.ubuntu_24[0].id, null))
  nat_instance_ami_id     = coalesce(var.nat_instance_ami, try(data.aws_ami.amazon_linux_2023[0].id, null))
  key_name                = coalesce(var.key_name, try(aws_key_pair.this[0].key_name, null))
  key_file_name           = "${coalesce(var.key_pair_name, "${var.name_prefix}-key")}.pem"
  deploy_ssh_key_to_nat   = coalesce(var.deploy_ssh_private_key_to_nat, var.key_name == null)
  ssh_identity_option     = var.key_name == null ? "-i ${local.key_file_name} " : ""
  # `ssh -i KEY -J HOST` does not pass KEY to the jump host, so the key is given to the proxy hop explicitly.
  ssh_jump_option         = "-o ProxyCommand=\"ssh ${local.ssh_identity_option}-o StrictHostKeyChecking=accept-new -W %h:%p ${var.nat_instance_ssh_user}@${aws_eip.nat.public_ip}\""
  nat_ssh_private_key_pem = coalesce(try(tls_private_key.ssh[0].private_key_pem, null), var.ssh_private_key_pem)

  common_tags = merge(
    var.tags,
    {
      Module = "airgap"
    }
  )

}
