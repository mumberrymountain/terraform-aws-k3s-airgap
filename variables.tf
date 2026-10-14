variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "airgap"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet that hosts the NAT instance."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet that hosts the isolated EC2 instances."
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "Single AZ for all subnets. Defaults to the first available AZ in the current region."
  type        = string
  default     = null
}

variable "key_name" {
  description = "Name of an existing EC2 key pair. When null, a new key pair is created and managed by this module."
  type        = string
  default     = null
}

variable "key_pair_name" {
  description = "Name for the module-created EC2 key pair. Defaults to {name_prefix}-key."
  type        = string
  default     = null
}

variable "deploy_ssh_private_key_to_nat" {
  description = "Install the SSH private key on the NAT instance for manual hop-by-hop SSH. Defaults to true when the module creates the key pair."
  type        = bool
  default     = null
}

variable "ssh_private_key_pem" {
  description = "Optional PEM private key to install on the NAT instance when using an existing key_name with deploy_ssh_private_key_to_nat."
  type        = string
  default     = null
  sensitive   = true
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the NAT instance."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "private_instance_count" {
  description = "Number of private EC2 instances to create in the isolated subnet."
  type        = number
  default     = 3

  validation {
    condition     = var.private_instance_count >= 1
    error_message = "private_instance_count must be at least 1."
  }
}

variable "private_instance_ami" {
  description = "AMI ID for private EC2 instances. When null, the latest Ubuntu 24.04 LTS AMI is used."
  type        = string
  default     = null
}

variable "private_instance_type" {
  description = "Instance type for private EC2 instances."
  type        = string
  default     = "t3.medium"
}

variable "private_instance_ssh_user" {
  description = "SSH username for private EC2 instances."
  type        = string
  default     = "ubuntu"
}

variable "nat_instance_ami" {
  description = "AMI ID for the NAT instance. When null, the latest Amazon Linux 2023 AMI is used."
  type        = string
  default     = null
}

variable "nat_instance_type" {
  description = "Instance type for the NAT instance."
  type        = string
  default     = "t3.micro"
}

variable "nat_instance_ssh_user" {
  description = "SSH username for the NAT instance."
  type        = string
  default     = "ec2-user"
}

variable "nat_root_volume_size" {
  description = "Root EBS volume size in GiB for the NAT instance."
  type        = number
  default     = 10

  validation {
    condition     = var.nat_root_volume_size >= 8
    error_message = "nat_root_volume_size must be at least 8 GiB."
  }
}

variable "private_root_volume_size" {
  description = "Root EBS volume size in GiB for private EC2 instances."
  type        = number
  default     = 20

  validation {
    condition     = var.private_root_volume_size >= 8
    error_message = "private_root_volume_size must be at least 8 GiB."
  }
}

variable "root_volume_type" {
  description = "EBS volume type for instance root volumes."
  type        = string
  default     = "gp3"
}

variable "root_volume_encrypted" {
  description = "Whether to encrypt instance root EBS volumes."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all supported resources."
  type        = map(string)
  default     = {}
}

################################################################################
# k3s
################################################################################

variable "k3s_version" {
  description = "k3s release installed on the private instances (e.g. v1.36.5+k3s1). The binary, air-gap image tarball and install script are pinned to this version."
  type        = string
  default     = "v1.36.5+k3s1"

  validation {
    condition     = can(regex("^v[0-9]+[.][0-9]+[.][0-9]+[+]k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must look like v1.36.5+k3s1."
  }
}

variable "k3s_server_count" {
  description = "Number of private instances that run as k3s servers (control plane). The rest join as agents. Values greater than 1 enable embedded etcd HA and must be odd."
  type        = number
  default     = 1

  validation {
    condition     = var.k3s_server_count >= 1 && var.k3s_server_count % 2 == 1
    error_message = "k3s_server_count must be an odd number >= 1."
  }
}
