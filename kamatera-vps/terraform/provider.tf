terraform {
  required_providers {
    kamatera = {
      source = "Kamatera/kamatera"
    }
  }
}

# Credentials via environment variables:
#   KAMATERA_API_CLIENT_ID
#   KAMATERA_API_SECRET
provider "kamatera" {}
