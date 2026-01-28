# DNS records for xdeca services on AWS Lightsail

resource "namecheap_domain_records" "enspyr" {
  domain = var.domain
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

  # Obsidian LiveSync
  record {
    hostname = "obsidian"
    type     = "A"
    address  = var.lightsail_ip
    ttl      = 1800
  }

  # Outline Wiki
  record {
    hostname = "wiki"
    type     = "A"
    address  = var.lightsail_ip
    ttl      = 1800
  }
}
