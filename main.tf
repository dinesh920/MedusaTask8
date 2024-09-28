provider "aws" {
  region = var.aws_region
}

# Fetch available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create a VPC for ECS
resource "aws_vpc" "medusa_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "medusa-vpc"
  }
}

# Create public subnets for the ECS tasks
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.medusa_vpc.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name = "medusa-public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.medusa_vpc.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = {
    Name = "medusa-public-subnet-2"
  }
}

# Create an Internet Gateway to allow access to the internet
resource "aws_internet_gateway" "medusa_igw" {
  vpc_id = aws_vpc.medusa_vpc.id
  tags = {
    Name = "medusa-igw"
  }
}

# Create a Route Table for public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.medusa_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.medusa_igw.id
  }
  tags = {
    Name = "medusa-public-route-table"
  }
}

# Associate the Route Table with the Subnets
resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Group to allow HTTP/HTTPS access
resource "aws_security_group" "medusa_sg" {
  name        = "medusa-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.medusa_vpc.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Cluster to run the Medusa app
resource "aws_ecs_cluster" "medusa_cluster" {
  name = "medusa-cluster"
}

# Create IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "Taskecrrole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "ecs_task_execution_role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition to run Medusa container
resource "aws_ecs_task_definition" "medusa" {
  family                   = "medusa-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = <<DEFINITION
  [
    {
      "name": "medusa",
      "image": "${var.image_url}",
      "memory": 512,
      "cpu": 256,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80
        }
      ]
    }
  ]
  DEFINITION
}

# ECS Service to run Medusa container
resource "aws_ecs_service" "medusa_service" {
  name            = "medusa-service"
  cluster         = aws_ecs_cluster.medusa_cluster.id
  task_definition = aws_ecs_task_definition.medusa.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
    security_groups = [aws_security_group.medusa_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.medusa_tg.arn
    container_name   = "medusa"
    container_port   = 80
  }
}

# Create a Load Balancer to distribute traffic
resource "aws_lb" "medusa_lb" {
  name               = "medusa-lb6"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.medusa_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  enable_deletion_protection = false
}

# Create a Target Group for the Load Balancer
resource "aws_lb_target_group" "medusa_tg" {
  name        = "medusa-target-group6"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.medusa_vpc.id
  
  # Set target type to 'ip' for compatibility with Fargate
  target_type = "ip"
}

# Create a Listener for the Load Balancer
resource "aws_lb_listener" "medusa_listener6" {
  load_balancer_arn = aws_lb.medusa_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.medusa_tg.arn
  }
}

# Outputs
output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.medusa_cluster.name
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.medusa_lb.dns_name
}

output "service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.medusa_service.name
}
