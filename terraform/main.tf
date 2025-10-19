terraform {
  required_version = ">= 1.5.0"
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

# VPC
resource "aws_vpc" "swarm_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "swarm-vpc"
    Project = "CA2-Swarm"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "swarm_igw" {
  vpc_id = aws_vpc.swarm_vpc.id

  tags = {
    Name    = "swarm-igw"
    Project = "CA2-Swarm"
  }
}

# Public Subnet
resource "aws_subnet" "swarm_public_subnet" {
  vpc_id                  = aws_vpc.swarm_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "swarm-public-subnet"
    Project = "CA2-Swarm"
  }
}

# Route Table
resource "aws_route_table" "swarm_public_rt" {
  vpc_id = aws_vpc.swarm_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.swarm_igw.id
  }

  tags = {
    Name    = "swarm-public-rt"
    Project = "CA2-Swarm"
  }
}

# Route Table Association
resource "aws_route_table_association" "swarm_public_rta" {
  subnet_id      = aws_subnet.swarm_public_subnet.id
  route_table_id = aws_route_table.swarm_public_rt.id
}

# Security Group
resource "aws_security_group" "swarm_sg" {
  name        = "swarm-sg"
  description = "Security group for Docker Swarm cluster"
  vpc_id      = aws_vpc.swarm_vpc.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Docker Swarm - Cluster management
  ingress {
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Docker Swarm cluster management"
  }

  # Docker Swarm - Node communication (TCP)
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Docker Swarm node communication TCP"
  }

  # Docker Swarm - Node communication (UDP)
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Docker Swarm node communication UDP"
  }

  # Docker Swarm - Overlay network
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Docker Swarm overlay network"
  }

  # Producer Health Endpoint
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Producer health endpoint"
  }

  # Processor Health Endpoint
  ingress {
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Processor health endpoint"
  }

  # Kafka (for debugging)
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Kafka internal"
  }

  # MongoDB (for debugging)
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "MongoDB internal"
  }

  # Egress - allow all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name    = "swarm-sg"
    Project = "CA2-Swarm"
  }
}

# Manager Node
resource "aws_instance" "swarm_manager" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.swarm_public_subnet.id
  vpc_security_group_ids = [aws_security_group.swarm_sg.id]
  
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "swarm-manager"
    Role    = "manager"
    Project = "CA2-Swarm"
  }
}

# Worker Node 1
resource "aws_instance" "swarm_worker_1" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.swarm_public_subnet.id
  vpc_security_group_ids = [aws_security_group.swarm_sg.id]
  
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "swarm-worker-1"
    Role    = "worker"
    Project = "CA2-Swarm"
  }
}

# Worker Node 2
resource "aws_instance" "swarm_worker_2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.swarm_public_subnet.id
  vpc_security_group_ids = [aws_security_group.swarm_sg.id]
  
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "swarm-worker-2"
    Role    = "worker"
    Project = "CA2-Swarm"
  }
}