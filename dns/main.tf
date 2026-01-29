# DNS records for xdeca services on AWS Lightsail

# Generic VPS record for xdeca.com CNAMEs
resource "namecheap_domain_records" "enspyr" {
  domain = "enspyr.co"
  mode   = "MERGE"

  record {
    hostname = "vps"
    type     = "A"
    address  = var.lightsail_ip
    ttl      = 1800
  }
}

resource "namecheap_domain_records" "xdeca" {
  domain = "xdeca.com"
  mode   = "MERGE"

  # Outline Wiki
  record {
    hostname = "wiki"
    type     = "A"
    address  = var.lightsail_ip
    ttl      = 1800
  }

  # Kan.bn (Tasks)
  record {
    hostname = "tasks"
    type     = "A"
    address  = var.lightsail_ip
    ttl      = 1800
  }

  # MinIO Storage (for Outline)
  record {
    hostname = "storage"
    type     = "A"
    address  = var.lightsail_ip
    ttl      = 1800
  }
}
