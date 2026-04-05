output "alb_dns_name" {
  description = "ALB DNS name — add this as a CNAME record in Cloudflare pointing to your domain_name"
  value       = module.ecs.alb_dns_name
}

output "acm_validation_records" {
  description = "DNS records to add in Cloudflare to validate the ACM certificate"
  value       = module.ecs.acm_validation_records
}
