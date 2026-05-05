# providers.tf

terraform {
  required_version = ">= 1.14.8"
  cloud {
    organization = "pinbraid-infra"
    workspaces {
      name = "slab-k3s-cluster"
    }
  }
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.102.0"
    }
  }
}

# Explicitly configure the provider
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  insecure  = true
  api_token = var.proxmox_api_token
}
