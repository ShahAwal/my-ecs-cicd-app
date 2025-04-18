# main.tf

# --- Networking ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a" # Adjust AZ if needed
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b" # Adjust AZ if needed
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-b"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

 resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-tasks-sg"
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # Allow traffic only from the ALB SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound connections (e.g., to pull images, connect to other AWS services)
  }

  tags = {
    Name = "${var.project_name}-tasks-sg"
  }
}


# --- ECR ---
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-repo"
  image_tag_mutability = "MUTABLE" # Or IMMUTABLE if preferred

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-ecr"
  }
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# --- IAM Roles ---
# ECS Task Execution Role: Allows ECS agent to pull images, write logs, etc.
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

   tags = {
    Name = "${var.project_name}-ecsTaskExecutionRole"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# (Optional) ECS Task Role: For application-specific permissions if needed later
# resource "aws_iam_role" "ecs_task_role" { ... }
# resource "aws_iam_policy" "app_policy" { ... }
# resource "aws_iam_role_policy_attachment" "ecs_task_role_app_policy" { ... }

# --- Log Group ---
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7 # Adjust as needed

  tags = {
    Name = "${var.project_name}-log-group"
  }
}

# --- Task Definition ---
# Note: Image is initially set to a placeholder; CI/CD will update this
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.app_cpu
  memory                   = var.app_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  # task_role_arn          = aws_iam_role.ecs_task_role.arn # Uncomment if using a specific task role

  container_definitions = jsonencode([{
    name      = "${var.project_name}-container" # This name is important for the CI/CD pipeline
    image     = "public.ecr.aws/nginx/nginx:latest" # Placeholder image - will be replaced by CI/CD
    cpu       = var.app_cpu
    memory    = var.app_memory
    essential = true
    portMappings = [{
      containerPort = var.app_port
      hostPort      = var.app_port # Not strictly needed for awsvpc but good practice
      protocol      = "tcp"
    }]
    logConfiguration = {
       logDriver = "awslogs"
       options = {
         "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
         "awslogs-region"        = var.aws_region
         "awslogs-stream-prefix" = "ecs"
       }
    }
  }])

  tags = {
    Name = "${var.project_name}-task-def"
  }

   # Add lifecycle rule to ignore image changes in Terraform after initial apply
  lifecycle {
    ignore_changes = [container_definitions]
  }
}


# --- Load Balancer ---
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  enable_deletion_protection = false # Set to true for production

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Required for Fargate

  health_check {
    enabled             = true
    path                = "/health" # Use the health check endpoint from app.js
    protocol            = "HTTP"
    matcher             = "200" # Expect HTTP 200 OK
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}


# --- ECS Service ---
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn # Use the initially created task definition ARN
  desired_count   = var.app_count
  launch_type     = "FARGATE"

  # Force new deployment on changes that require it (like task definition update)
  force_new_deployment = true

  network_configuration {
    subnets         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true # Assign public IPs to tasks in public subnets for simplicity (e.g., pulling images if needed, though ECR access can use VPC endpoints)
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "${var.project_name}-container" # Must match the name in container_definitions
    container_port   = var.app_port
  }

  # Depends on the ALB listener to ensure it exists before the service tries to attach
  depends_on = [aws_lb_listener.http]

  tags = {
    Name = "${var.project_name}-service"
  }

  # Ignore task_definition changes made outside Terraform (by the CI/CD pipeline)
  # Ignore desired_count changes if you want to scale manually or via autoscaling later
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

# --- GitHub Actions OIDC Integration ---

# 1. OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # Standard GitHub Actions OIDC thumbprint (verify if needed)
}

# 2. IAM Role for GitHub Actions
data "aws_iam_policy_document" "github_actions_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Condition to scope access ONLY to your specific GitHub repo and main branch
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # IMPORTANT: Update 'your-github-username/your-repo-name' below
      values = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions_role" {
  name               = "${var.project_name}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role_policy.json
  description        = "IAM role for GitHub Actions CI/CD"

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

# 3. Permissions Policy for the Role
data "aws_iam_policy_document" "github_actions_permissions" {
  # Permissions needed by the CI/CD pipeline
  statement {
    actions = [
      # ECR Permissions
      "ecr:GetAuthorizationToken", # Implicitly covered by BatchGetImage/GetDownloadUrlForLayer, but explicit is fine
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]
    effect    = "Allow"
    resources = [aws_ecr_repository.app.arn] # Scope ECR permissions to the specific repo
  }

  statement {
    actions = [
       # Allow login to ECR (needed for `aws ecr get-login-password`)
      "ecr:GetAuthorizationToken"
    ]
    effect = "Allow"
    resources = ["*"] # This action requires a wildcard resource
  }

  statement {
    actions = [
      # ECS Permissions (scoped where possible)
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:ListTasks" # Useful for checking deployment status
    ]
    effect    = "Allow"
    # Scope to resources within the cluster where possible
    resources = [
      aws_ecs_service.main.id,
      aws_ecs_task_definition.app.arn, # Allows describing the specific task def family
      "${aws_ecs_task_definition.app.arn}:*", # Allows describing specific revisions
      aws_ecs_cluster.main.arn
    ]
  }
   # Required for RegisterTaskDefinition if you grant task execution role permissions
  statement {
    actions   = ["iam:PassRole"]
    effect    = "Allow"
    resources = [
        aws_iam_role.ecs_task_execution_role.arn,
        # Add aws_iam_role.ecs_task_role.arn here if you defined and used one
    ]
    # Condition to ensure PassRole is only used by ECS service
    condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "github_actions_policy" {
  name        = "${var.project_name}-github-actions-policy"
  description = "Permissions policy for GitHub Actions role"
  policy      = data.aws_iam_policy_document.github_actions_permissions.json
}

resource "aws_iam_role_policy_attachment" "github_actions_attach" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}
