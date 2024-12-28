# BY - TUSHAR SRIVASTAVA
# Create a highly available, scalable web application infrastructure on AWS using Terraform.
# The infrastructure should consist of a custom VPC, EC2 instances, Security Groups, and an Application
# Load Balancer (ALB). The application should be able to handle traffic from the ALB and be accessible over the internet.
terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 4.0"
    }
  }
}

provider "aws" {
    region = "us-east-1"
    access_key = "************************"
    secret_key = "****************************************"
}

# ------------------------------------------- step 1 - custom vpc -----------------------------------------------------
# Create a custom VPC with a CIDR block of 10.0.0.0/16.
resource "aws_vpc" "task_vpc" {
  tags = {
        Name = "task-vpc"
  } 
  cidr_block = "10.0.0.0/16"
}

# ------------------------------------------ step 2 - public subnet ----------------------------------------------------
# Create two public subnets in different Availability Zones (AZs) (e.g., 10.0.1.0/24 and 10.0.2.0/24).
resource "aws_subnet" "task_public_subnet_1" {
  tags = {
    Name = "task-public-subnet-1"
  }
  vpc_id = aws_vpc.task_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "task_public_subnet_2" {
  tags = {
    Name = "task-public-subnet-2"
  }
  vpc_id = aws_vpc.task_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# ------------------------------------------ step 3 - internet gateway ------------------------------------------------
# Create an Internet Gateway (IGW) and attach it to the VPC.
resource "aws_internet_gateway" "task_internet_gateway" {
  tags = {
    Name = "task-internet-gateway"
  }
  vpc_id = aws_vpc.task_vpc.id  
}

# ---------------------------------------- step 4 - route table & association ------------------------------------------
# Create appropriate route tables to allow outbound internet access from the public subnets via the IGW.
# Associate the route tables with the public subnets.
resource "aws_route_table" "task_route_table_1" {
  tags = {
    Name = "task-route-table-1"
  }
  vpc_id = aws_vpc.task_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.task_internet_gateway.id
  }
}

resource "aws_route_table_association" "task_rta_1" {
  subnet_id = aws_subnet.task_public_subnet_1.id
  route_table_id = aws_route_table.task_route_table_1.id
}

resource "aws_route_table" "task_route_table_2" {
  tags = {
    Name = "task-route-table-2"
  }
  vpc_id = aws_vpc.task_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.task_internet_gateway.id
  }
}

resource "aws_route_table_association" "task_rta_2" {
  subnet_id = aws_subnet.task_public_subnet_2.id
  route_table_id = aws_route_table.task_route_table_2.id
}

# ------------------------------------------- step 5 - security group --------------------------------------------------
# Create a Security Group for the ALB that allows HTTP (port 80) access from anywhere.
resource "aws_security_group" "task_security_group_alb" {
  tags = {
    Name = "task-security-group-alb"
  }
  vpc_id = aws_vpc.task_vpc.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a Security Group for the EC2 instances that:
# Allows incoming HTTP traffic from the ALB's security group (use the ALB's security group as the source).
# Allows outbound traffic to any destination (so EC2 instances can connect to the internet if needed).
resource "aws_security_group" "task_security_group_instances" {
  tags = {
    Name = "task-security-group-instances"
  }
  vpc_id = aws_vpc.task_vpc.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = [aws_security_group.task_security_group_alb.id]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------------------- step 6 - key & instance ----------------------------------------------------
# Launch two EC2 instances in the public subnets, one in each AZ.
# Use the Amazon Linux 2 AMI and configure it to run a simple HTTP server (e.g., using a startup script to install and
# start an Apache or Nginx web server).
# Ensure the instances use the EC2 security group created in step 2.
resource "tls_private_key" "task_key" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "task_key_pair" {
  key_name = "task.pem"
  public_key = tls_private_key.task_key.public_key_openssh
}

resource "local_file" "task_local_file" {
  content = tls_private_key.task_key.private_key_pem
  filename = "task"
}

resource "aws_instance" "task_instance_1" {
  tags = {
    Name = "task-instance-1"
  }
  ami = "ami-0182f373e66f89c85"
  instance_type = "t2.micro"
  key_name = "task.pem"
  subnet_id = aws_subnet.task_public_subnet_1.id
  vpc_security_group_ids = [aws_security_group.task_security_group_instances.id]
  user_data = file("instance1.sh")
  associate_public_ip_address = true
  availability_zone = "us-east-1a"
}

resource "aws_instance" "task_instance_2" {
  tags = {
    Name = "task-instance-2"
  }
  ami = "ami-0182f373e66f89c85"
  instance_type = "t2.micro"
  key_name = "task.pem"
  subnet_id = aws_subnet.task_public_subnet_2.id
  vpc_security_group_ids = [aws_security_group.task_security_group_instances.id]
  user_data = file("instance2.sh")
  associate_public_ip_address = true
  availability_zone = "us-east-1b"
}

# # --------------------------------------------- step 7 - alb ---------------------------------------------------------
# Create an Application Load Balancer (ALB) that spans the two public subnets.
resource "aws_alb" "task_alb" {
  tags = {
    Name = "task-alb"
  }
  security_groups = [aws_security_group.task_security_group_alb.id]
  subnets = [aws_subnet.task_public_subnet_1.id, aws_subnet.task_public_subnet_2.id]
}

# Create a Target Group that points to the EC2 instances (use HTTP as the protocol and port 80).
resource "aws_alb_target_group" "task_alb_target_group" {
  tags = {
    Name = "task-alb-target-group"
  }
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.task_vpc.id
  target_type = "instance"
}

# Register the two EC2 instances with the Target Group.
resource "aws_alb_target_group_attachment" "task_alb_target_group_attachment_1" {
  target_group_arn = aws_alb_target_group.task_alb_target_group.arn
  target_id = aws_instance.task_instance_1.id
}

resource "aws_alb_target_group_attachment" "task_alb_target_group_attachment_2" {
  target_group_arn = aws_alb_target_group.task_alb_target_group.arn
  target_id = aws_instance.task_instance_2.id
}

# Configure a listener for the ALB to forward HTTP traffic (port 80) to the Target Group.
resource "aws_alb_listener" "task_alb_listener" {
  tags = {
    Name = "task-alb-listener"
  }
  load_balancer_arn = aws_alb.task_alb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.task_alb_target_group.arn
  }
}

# --------------------------------------------- step 8 - output --------------------------------------------------------
# Ensure that the ALB's DNS name is outputted in Terraform so that the application can be accessed through the ALB.
# Access the ALB's DNS name in your browser and verify that traffic is being distributed to the EC2 instances.
output "alb_dns_name" {
  description = "The DNS name of ALB"
  value = aws_alb.task_alb.dns_name
}