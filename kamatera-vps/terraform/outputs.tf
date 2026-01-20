output "instance_id" {
  description = "Server ID"
  value       = kamatera_server.xdeca.id
}

output "instance_public_ip" {
  description = "Public IP address"
  value       = kamatera_server.xdeca.public_ips[0]
}

output "instance_private_ip" {
  description = "Private IP address"
  value       = kamatera_server.xdeca.private_ips[0]
}

output "datacenter" {
  description = "Datacenter location"
  value       = "${var.datacenter_name}, ${var.datacenter_country}"
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh ubuntu@${kamatera_server.xdeca.public_ips[0]}"
}
