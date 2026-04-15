output "cluster_name" {
  description = "ECS cluster name — pass to connect-db.sh via ECS_CLUSTER env var"
  value       = aws_ecs_cluster.bastion.name
}

output "task_definition" {
  description = "Task definition family — pass to connect-db.sh via TASK_DEFINITION env var"
  value       = aws_ecs_task_definition.bastion.family
}

output "security_group_id" {
  description = "Bastion security group ID — pass to connect-db.sh via SECURITY_GROUP_ID env var"
  value       = aws_security_group.bastion.id
}

output "admin_bucket" {
  description = "S3 bucket name for admin scripts"
  value       = aws_s3_bucket.admin.bucket
}

output "migrator_task_definition" {
  description = "Migrator task definition family — pass to migrate-db.sh via TASK_DEFINITION env var"
  value       = aws_ecs_task_definition.db_migrator.family
}

output "migrator_task_execution_role_arn" {
  description = "Migrator task execution role ARN"
  value       = aws_iam_role.migrator_task_execution.arn
}

output "migrator_task_role_arn" {
  description = "Migrator task role ARN"
  value       = aws_iam_role.migrator_task.arn
}
