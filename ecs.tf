# 1. The ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "my-cluster"
}

# 2. The Task Definition (The Blueprint)
resource "aws_ecs_task_definition" "app" {
  family                   = "my-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_exec.arn

  container_definitions = jsonencode([{
    name      = "my-container"
    image     = "901504599528.dkr.ecr.us-east-1.amazonaws.com/my-app-repo:latest"
    essential = true
    
    # Note: These use camelCase because they are inside a JSON string for the AWS API
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
    
    # Optional: Log to CloudWatch (Highly recommended for debugging)
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/my-app"
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# 3. The ECS Service (The Manager)
resource "aws_ecs_service" "main" {
  name            = "my-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    # Since you have a NAT Gateway in vpc.tf, we use the Private Subnet
    subnets          = [aws_subnet.private_1.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "my-container" # Must match 'name' in container_definitions above
    container_port   = 80
  }
}

# 4. CloudWatch Log Group (Helps you see Python errors)
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/my-app"
  retention_in_days = 7
}