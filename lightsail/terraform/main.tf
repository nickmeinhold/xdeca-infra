terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Static IP for the instance
resource "aws_lightsail_static_ip" "xdeca" {
  name = "xdeca-ip"
}

# Attach static IP to instance
resource "aws_lightsail_static_ip_attachment" "xdeca" {
  static_ip_name = aws_lightsail_static_ip.xdeca.name
  instance_name  = aws_lightsail_instance.xdeca.name
}

# Main instance
resource "aws_lightsail_instance" "xdeca" {
  name              = var.instance_name
  availability_zone = "${var.region}a"
  blueprint_id      = "ubuntu_24_04"
  bundle_id         = var.bundle_id
  key_pair_name     = aws_lightsail_key_pair.xdeca.name

  user_data = templatefile("${path.module}/cloud-init.yaml.tpl", {
    ssh_public_key = var.ssh_public_key
  })

  tags = {
    Project = "xdeca"
  }
}

# SSH key pair
resource "aws_lightsail_key_pair" "xdeca" {
  name       = "xdeca-key"
  public_key = var.ssh_public_key
}

# Firewall - open required ports
resource "aws_lightsail_instance_public_ports" "xdeca" {
  instance_name = aws_lightsail_instance.xdeca.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
  }

  # Matrix federation
  port_info {
    protocol  = "tcp"
    from_port = 8448
    to_port   = 8448
  }
}

# Outputs
output "public_ip" {
  value       = aws_lightsail_static_ip.xdeca.ip_address
  description = "Static public IP address"
}

output "instance_name" {
  value = aws_lightsail_instance.xdeca.name
}
