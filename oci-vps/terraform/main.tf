# Read SSH public key
data "local_file" "ssh_public_key" {
  filename = pathexpand(var.ssh_public_key_path)
}

# Cloud-init configuration
data "cloudinit_config" "server" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init.yaml.tpl", {
      domain = var.domain
    })
  }
}

# Compute Instance
resource "oci_core_instance" "xdeca" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = var.instance_name
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = true
    display_name     = "${var.instance_name}-vnic"
  }

  metadata = {
    ssh_authorized_keys = data.local_file.ssh_public_key.content
    user_data           = data.cloudinit_config.server.rendered
  }

  # Prevent replacement on cloud-init changes
  lifecycle {
    ignore_changes = [
      metadata["user_data"]
    ]
  }
}
