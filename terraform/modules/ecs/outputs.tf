output "alb_dns_name" {
  description = "ALB DNS name — use this as the CNAME target in the domain manager DNS config"
  value       = aws_lb.main.dns_name
}

output "acm_validation_records" {
  description = "DNS records to add in the domain manager DNS config to validate the ACM certificate"
  value = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}
