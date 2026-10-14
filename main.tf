resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-public"
  })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.availability_zone

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-private"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "nat" {
  name        = "${var.name_prefix}-nat-sg"
  description = "NAT instance: SSH from allowed sources only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from allowed CIDR blocks"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr_blocks
  }

  ingress {
    description = "k3s air-gap artifact server from the private subnet"
    from_port   = local.k3s_artifact_port
    to_port     = local.k3s_artifact_port
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-sg"
  })
}

resource "aws_security_group" "private" {
  name        = "${var.name_prefix}-private-sg"
  description = "Private instances: reachable from and able to reach only the NAT instance and each other"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "SSH from NAT instance"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.nat.id]
  }

  ingress {
    description = "k3s intra-cluster traffic (API, kubelet, flannel VXLAN, etcd)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "k3s API server from NAT/bastion (SSH tunnel)"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.nat.id]
  }

  egress {
    description     = "To NAT instance only (k3s artifact server)"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.nat.id]
  }

  egress {
    description = "k3s intra-cluster traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-private-sg"
  })
}

resource "aws_instance" "private" {
  count = var.private_instance_count

  ami                    = local.private_instance_ami_id
  instance_type          = var.private_instance_type
  subnet_id              = aws_subnet.private.id
  private_ip             = local.private_instance_ips[count.index]
  vpc_security_group_ids = [aws_security_group.private.id]
  key_name               = local.key_name

  user_data = templatefile("${path.module}/templates/k3s_node_user_data.sh.tftpl", {
    role                = count.index < var.k3s_server_count ? "server" : "agent"
    artifact_url        = local.k3s_artifact_url
    arch                = local.k3s_arch
    images_file_name    = local.k3s_images_file_name
    config_yaml         = local.k3s_node_configs[count.index]
    ssh_user            = var.private_instance_ssh_user
    private_subnet_cidr = var.private_subnet_cidr
    nat_private_ip      = local.nat_static_ip
    pod_cidr            = local.k3s_pod_cidr
    service_cidr        = local.k3s_service_cidr
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.private_root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = var.root_volume_encrypted
    delete_on_termination = true
  }

  lifecycle {
    precondition {
      condition     = var.k3s_server_count <= var.private_instance_count
      error_message = "k3s_server_count must not exceed private_instance_count."
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-private-${count.index + 1}"
    Role = count.index < var.k3s_server_count ? "k3s-server" : "k3s-agent"
  })
}

resource "aws_instance" "nat" {
  ami                         = local.nat_instance_ami_id
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public.id
  private_ip                  = local.nat_static_ip
  vpc_security_group_ids      = [aws_security_group.nat.id]
  key_name                    = local.key_name
  source_dest_check           = false
  associate_public_ip_address = true
  user_data = templatefile("${path.module}/templates/nat_user_data.sh.tftpl", {
    deploy_ssh_key       = local.deploy_ssh_key_to_nat
    private_key_pem      = local.nat_ssh_private_key_pem
    nat_ssh_user         = var.nat_instance_ssh_user
    private_ssh_user     = var.private_instance_ssh_user
    private_host_ips     = aws_instance.private[*].private_ip
    k3s_version_url      = local.k3s_version_url
    k3s_arch             = local.k3s_arch
    k3s_images_file_name = local.k3s_images_file_name
    k3s_artifact_port    = local.k3s_artifact_port
  })

  root_block_device {
    volume_size           = var.nat_root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = var.root_volume_encrypted
    delete_on_termination = true
  }

  lifecycle {
    precondition {
      condition     = !local.deploy_ssh_key_to_nat || local.nat_ssh_private_key_pem != null
      error_message = "deploy_ssh_private_key_to_nat requires a module-managed key pair or ssh_private_key_pem."
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat"
    Role = "nat"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-eip"
  })
}

resource "aws_eip_association" "nat" {
  allocation_id = aws_eip.nat.id
  instance_id   = aws_instance.nat.id
}
