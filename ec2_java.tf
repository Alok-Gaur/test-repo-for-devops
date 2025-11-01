terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------- VARIABLES ----------------
variable "aws_region" {
  default = "us-east-1"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH access"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name where your JAR is stored"
  type        = string
}

variable "jar_key" {
  description = "S3 key (path) of your JAR file, e.g., app/myapp.jar"
  type        = string
}

variable "allow_ssh_from" {
  description = "CIDR allowed to SSH (restrict this in production)"
  default     = "0.0.0.0/0"
}

variable "allow_http_from" {
  default = "0.0.0.0/0"
}

# ---------------- RESOURCES ----------------

# Fetch latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["137112412989"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Simple networking
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "tf-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = { Name = "tf-public-subnet" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id
  tags = { Name = "tf-igw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "tf-public-rt" }
}

resource "aws_route_table_association" "assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group
resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.vpc.id
  name   = "java-app-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allow_ssh_from]
    description = "SSH Access"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allow_http_from]
    description = "HTTP Access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "tf-java-sg" }
}

# IAM role for EC2 -> S3 access
resource "aws_iam_role" "ec2_role" {
  name = "tf-ec2-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "s3_policy" {
  name = "tf-s3-read-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_instance_profile" "profile" {
  name = "tf-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 instance
resource "aws_instance" "java_app" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.profile.name

  user_data = <<-EOF
    #!/bin/bash
    set -e
    yum update -y
    yum install -y java-11-openjdk awscli

    mkdir -p /opt/app
    cd /opt/app
    aws s3 cp s3://${var.bucket_name}/${var.jar_key} app.jar

    cat <<EOL > /etc/systemd/system/java-app.service
    [Unit]
    Description=Java App
    After=network.target

    [Service]
    User=ec2-user
    ExecStart=/usr/bin/java -jar /opt/app/app.jar
    Restart=always

    [Install]
    WantedBy=multi-user.target
    EOL

    systemctl daemon-reload
    systemctl enable java-app
    systemctl start java-app
  EOF

  tags = {
    Name = "java-app-instance"
  }
}

# Outputs
output "instance_ip" {
  value = aws_instance.java_app.public_ip
}

output "instance_dns" {
  value = aws_instance.java_app.public_dns
}
