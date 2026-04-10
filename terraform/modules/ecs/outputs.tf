output "alb_dns_name" {
  description = "ALB DNS name — use this as the CNAME target in the domain manager DNS config"
  value       = aws_lb.main.dns_name
}
