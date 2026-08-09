variable "aws_region" {
  description = "The region where AWS EC2 instance running"
  type        = string
}

variable "instance_type" {
  description = "The type of the EC2 instance"
  type        = string
}

variable "vpc_cidr" {
  description = "The cidr block of the VPC"
  type        = string
}

variable "subnet_cidr" {
  description = "The cidr block of the subnet"
  type        = string
}

variable "principal_public_ip" {
  description = "The Public IP allow to connect via SSH"
  type        = string
}

variable "secret_name" {
  description = "The name of the secrets in Secret Manager"
  type        = string
}

variable "user_name" {
  description = "The user's name"
  type        = string
}

variable "user_password" {
  description = "The user's password"
  type = string
}