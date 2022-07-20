output "nlb_dns_name" {
  value = aws_lb.fme_server_nlb.dns_name
  description = "Public dns name of the application load balancer"
}

output "core_target_group_arn" {
  value = aws_lb_listener.fme_server_engine-registration.arn
  description = "The ARN of the FME Server engine registration target group"
}

