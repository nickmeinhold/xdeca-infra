variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2" # Sydney
}

variable "instance_name" {
  description = "Name of the Lightsail instance"
  type        = string
  default     = "xdeca"
}

variable "bundle_id" {
  description = "Lightsail bundle (instance size)"
  type        = string
  default     = "small_3_0" # 2GB RAM, 1 vCPU, 60GB SSD, $12/mo
  # Options:
  # nano_3_0    - 512MB, 0.25 vCPU, 20GB  - $3.50/mo
  # micro_3_0   - 1GB,   0.5 vCPU,  40GB  - $5/mo
  # small_3_0   - 2GB,   1 vCPU,    60GB  - $12/mo
  # medium_3_0  - 4GB,   2 vCPU,    80GB  - $24/mo
  # large_3_0   - 8GB,   2 vCPU,    160GB - $48/mo
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}
