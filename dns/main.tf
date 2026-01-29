# DNS records for xdeca services on AWS Lightsail

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
