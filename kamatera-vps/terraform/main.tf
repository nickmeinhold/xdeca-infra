# Read SSH public key
data "local_file" "ssh_public_key" {
  filename = pathexpand(var.ssh_public_key_path)
}

# Select datacenter
data "kamatera_datacenter" "main" {
  country = var.datacenter_country
  name    = var.datacenter_name
}

# Select OS image
data "kamatera_image" "ubuntu" {
  datacenter_id = data.kamatera_datacenter.main.id
  os            = var.os
  code          = var.os_version
}

# Startup script (cloud-init style)
locals {
  startup_script = templatefile("${path.module}/startup.sh.tpl", {
    domain         = var.domain
    ssh_public_key = trimspace(data.local_file.ssh_public_key.content)
  })
}

# Create server
resource "kamatera_server" "xdeca" {
  name                    = var.instance_name
  datacenter_id           = data.kamatera_datacenter.main.id
  cpu_type                = var.cpu_type
  cpu_cores               = var.cpu_cores
  ram_mb                  = var.ram_mb
  disk_sizes_gb           = [var.disk_size_gb]
  billing_cycle           = var.billing_cycle
  monthly_traffic_package = "t1000"  # 1TB traffic for Sydney datacenter
  image_id                = data.kamatera_image.ubuntu.id

  # SSH key auth via startup script
  startup_script = local.startup_script

  # WAN network with auto IP
  network {
    name = "wan"
  }

  # Allow recreation for changes that require it
  allow_recreate = false
}
