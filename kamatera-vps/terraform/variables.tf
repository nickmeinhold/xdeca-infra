# Datacenter Configuration
variable "datacenter_country" {
  description = "Country for the datacenter"
  type        = string
  default     = "Australia"
}

variable "datacenter_name" {
  description = "Datacenter name"
  type        = string
  default     = "Sydney"
}

# Instance Configuration
variable "instance_name" {
  description = "Server name"
  type        = string
  default     = "xdeca"
}

variable "cpu_type" {
  description = "CPU type (A=Availability, B=General, T=Burstable, D=Dedicated)"
  type        = string
  default     = "B"
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "ram_mb" {
  description = "RAM in MB"
  type        = number
  default     = 4096
}

variable "disk_size_gb" {
  description = "Primary disk size in GB"
  type        = number
  default     = 50
}

variable "billing_cycle" {
  description = "Billing cycle (hourly or monthly)"
  type        = string
  default     = "monthly"
}

# OS Image
variable "os" {
  description = "Operating system"
  type        = string
  default     = "Ubuntu"
}

variable "os_version" {
  description = "OS version code"
  type        = string
  default     = "24.04 64bit"
}

# SSH Configuration
variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# Domain Configuration
variable "domain" {
  description = "Base domain for services"
  type        = string
  default     = "yourdomain.com"
}
