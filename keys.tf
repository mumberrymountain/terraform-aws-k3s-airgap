resource "tls_private_key" "ssh" {
  count = var.key_name == null ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  count = var.key_name == null ? 1 : 0

  key_name   = coalesce(var.key_pair_name, "${var.name_prefix}-key")
  public_key = tls_private_key.ssh[0].public_key_openssh

  tags = merge(local.common_tags, {
    Name = coalesce(var.key_pair_name, "${var.name_prefix}-key")
  })
}
