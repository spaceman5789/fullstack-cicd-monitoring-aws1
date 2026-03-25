variable "project_name" { type = string }
variable "environment" { type = string }
variable "db_name" { type = string }
variable "db_username" { type = string }
variable "instance_class" { type = string }
variable "allocated_storage" { type = number }
variable "db_subnets" { type = list(string) }
variable "security_groups" { type = list(string) }
