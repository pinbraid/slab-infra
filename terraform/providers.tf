terraform {
  required_version = "1.14.8"
  cloud {
    organization = "pinbraid-infra" # Change this
    workspaces {
      name = "slab-k3s-cluster"
    }
  }
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.102.0" # Or latest
    }
  }
}

provider "proxmox" {
  # We will pass the endpoint, token_id, and secret via environment variables later 
  # so they are never hardcoded in your Git repo.
  insecure = true # Assuming self-signed cert on The Slab
}
