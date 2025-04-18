# outputs.tf

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

 output "ecs_task_definition_family" {
   description = "Family name of the ECS Task Definition"
   value       = aws_ecs_task_definition.app.family
 }

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions_role.arn
}

 output "container_name" {
   description = "Name of the container defined in the task definition"
   # This fetches the name from the first container definition. Adjust if you have multiple.
   value       = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].name
 }
