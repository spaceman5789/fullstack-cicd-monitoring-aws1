variable "project_name" { type = string }
variable "environment" { type = string }
variable "instance_type" { type = string }
variable "subnet_id" { type = string }
variable "security_groups" { type = list(string) }
variable "aws_region" { type = string }
