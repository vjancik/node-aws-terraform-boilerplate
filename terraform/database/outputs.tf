# NOTE: uncomment once the RDS Proxy is re-enabled (requires non-free-tier account)
# output "proxy_endpoint" {
#   description = "RDS Proxy endpoint — use this in app DB connection strings instead of the RDS endpoint directly"
#   value       = aws_db_proxy.main.endpoint
# }

output "db_endpoint" {
  description = "RDS instance endpoint — replace with proxy_endpoint once RDS Proxy is enabled"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "Database port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}
