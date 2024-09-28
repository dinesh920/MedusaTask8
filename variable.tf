# AWS Region
variable "aws_region" {
  description = "The AWS region where resources will be created"
  default     = "us-east-1"
}

# VPC CIDR block
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

# Public Subnet 1 CIDR block
variable "public_subnet_1_cidr" {
  description = "CIDR block for the public subnet 1"
  default     = "10.0.1.0/24"
}

# Public Subnet 2 CIDR block
variable "public_subnet_2_cidr" {
  description = "CIDR block for the public subnet 2"
  default     = "10.0.2.0/24"
}

# Image URL for the Medusa container
variable "image_url" {
  description = "URL of the Docker image in ECR"
}
