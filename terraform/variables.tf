# Define the variable so Terraform expects it
variable "proxmox_api_token" {
  description = "The API token for the Proxmox provider"
  type        = string
  sensitive   = true
}

variable "proxmox_endpoint" {
  description = "The Proxmox API endpoint URL"
  type        = string
}