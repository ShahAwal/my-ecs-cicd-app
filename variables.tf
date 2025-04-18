# variables.tf
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1" # Choose your preferred region
}

variable "project_name" {
  description = "A unique name for the project used for tagging and naming resources"
  type        = string
  default     = "my-fargate-app"
}

variable "app_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 3000
}

variable "app_cpu" {
  description = "Fargate task CPU units (e.g., 256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "app_memory" {
  description = "Fargate task memory units (in MiB)"
  type        = number
  default     = 512
}

variable "app_count" {
  description = "Number of docker containers to run"
  type        = number
  default     = 1 # Start with 1, can be scaled later
}

variable "github_repo" {
  description = "GitHub repository name (e.g., 'your-username/your-repo-name')"
  type        = string
  # Replace with your actual GitHub repo path
  # Example: default = "my-github-user/my-ecs-cicd-app"
}
