variable "vpc_name" {
  type        = string
  description = "Virtual private cloud name"
}

variable "fme_core_image_id" {
  type        = string
  description = "Id of the FME Sever core image"
}

variable "sg_id" {
  type        = string
  description = "Security group id for FME Flow deployment"
}

variable "iam_instance_profile" {
  type        = string
  description = "IAM profile to be attached to the instances"
}

variable "rds_secrets_arn" {
  type        = string
  description = "Secret id for FME Flow backend database"
}

variable "fsx_secrets_arn" {
  type        = string
  description = "Secret id for FME Flow storage"
}

variable "ssm_document_name" {
  type        = string
  description = "Name of the SSM document used to join instances to the Active Directory"
}

variable "alb_dns_name" {
  type        = string
  description = "Public dns name of the application load balancer"
}

variable "core_target_group_arn" {
  type        = string
  description = "The ARN of the FME Flow core target group"
}

variable "websocket_target_group_arn" {
  type        = string
  description = "The ARN of the FME Flow websocket target group"
}

variable "engine_registration_target_group_arn" {
  type        = string
  description = "The ARN of the FME Flow engine registration target group"
}

variable "private_sn_az2_id" {
  type        = string
  description = "Private subnet id in the second availability zone"
}

variable "private_sn_az1_id" {
  type        = string
  description = "Private subnet id in the first availability zone"
}

variable "owner" {
  type        = string
  description = "Resource owner for tagging purposes"
}