module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"

  name = "Terraform_FME"

  instance_type          = "t3.medium"
  key_name               = "merline_ec2_key"

  tags = {
    Project     = "UC2025"
  }
}
