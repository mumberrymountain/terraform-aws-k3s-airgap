variable "aws_region" {
  description = "AWS region for the example deployment."
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_access_key" {
  description = "AWS access key ID. Leave null to use environment variables or the shared credentials file."
  type        = string
  default     = null
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret access key. Leave null to use environment variables or the shared credentials file."
  type        = string
  default     = null
  sensitive   = true
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "airgap-practice"
}

variable "key_name" {
  description = "Use an existing EC2 key pair by name. When null, the module creates and manages a new key pair."
  type        = string
  default     = null
}

variable "key_pair_name" {
  description = "Name for the module-created EC2 key pair. Defaults to {name_prefix}-key."
  type        = string
  default     = null
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the NAT instance."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "private_instance_count" {
  description = "Number of private EC2 instances."
  type        = number
  default     = 3
}

variable "private_instance_ami" {
  description = "Optional AMI override for private instances."
  type        = string
  default     = null
}

variable "private_instance_type" {
  description = "Instance type for private EC2 instances."
  type        = string
  default     = "t3.medium"
}

variable "nat_instance_ami" {
  description = "Optional AMI override for the NAT instance."
  type        = string
  default     = null
}

variable "nat_instance_type" {
  description = "Instance type for the NAT instance."
  type        = string
  default     = "t3.micro"
}

variable "nat_root_volume_size" {
  description = "Root EBS volume size in GiB for the NAT instance."
  type        = number
  default     = 10
}

variable "private_root_volume_size" {
  description = "Root EBS volume size in GiB for private EC2 instances."
  type        = number
  default     = 20
}

variable "k3s_version" {
  description = "k3s release to install."
  type        = string
  default     = "v1.36.5+k3s1"
}

variable "k3s_server_count" {
  description = "Number of k3s server nodes (odd). The remaining private instances join as agents."
  type        = number
  default     = 1
}
