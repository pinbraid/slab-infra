output "proxmox_hostnames" {
  description = "A list of Proxmox physical hosts"
  value       = data.proxmox_virtual_environment_nodes.available_nodes.names
}

output "proxmox_vms" {
  description = "A list of QEMU VMs on The Slab"
  value       = data.proxmox_virtual_environment_vms.all_vms.vms[*].name
}

output "proxmox_lxcs" {
  description = "Names of LXC Containers on The Slab (e.g., Tailscale, Pi-Hole)"
  value       = data.proxmox_virtual_environment_containers.all_lxcs.containers[*]
}