terraform {
  backend "s3" {
    bucket         = "fullstack-deploy-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "eu-north-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}
