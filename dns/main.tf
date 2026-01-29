# DNS records for xdeca services on AWS Lightsail

resource "namecheap_domain_records" "enspyr" {
  domain = "enspyr.co"
  mode   = "MERGE"

  # OpenProject
  record {
    hostname = "openproject"
    type     = "A"
    address  = var.lightsail_ip
    ttl      = 1800
  }

  # Calendar Sync (OpenProject ↔ Google Calendar)
  record {
    hostname = "calendar-sync"
    type     = "A"
    address  = var.lightsail_ip
    ttl      = 1800
  }

  # Outline Storage (MinIO)
  record {
    hostname = "storage"
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
}
