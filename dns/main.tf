# DNS records for xdeca services on Kamatera VPS

resource "namecheap_domain_records" "enspyr" {
  domain = var.domain
  mode   = "MERGE"

  # OpenProject
  record {
    hostname = "openproject"
    type     = "A"
    address  = var.kamatera_ip
    ttl      = 1800
  }

  # Twenty CRM
  record {
    hostname = "twenty"
    type     = "A"
    address  = var.kamatera_ip
    ttl      = 1800
  }

  # Calendar Sync (OpenProject ↔ Google Calendar)
  record {
    hostname = "calendar-sync"
    type     = "A"
    address  = var.kamatera_ip
    ttl      = 1800
  }
}
