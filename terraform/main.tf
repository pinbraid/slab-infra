#--------------------------------------------------------
# SONAR PING: Ask Proxmox for the names of its nodes
# --------------------------------------------------------
data "proxmox_virtual_environment_nodes" "available_nodes" {}

data "proxmox_virtual_environment_containers" "all_lxcs" {
  # Dynamically grabs the first node name it finds from the block above
  node_name = data.proxmox_virtual_environment_nodes.available_nodes.names[0]
}

data "proxmox_virtual_environment_vms" "all_vms" {
  # Dynamically grabs the first node name it finds from the block above
  node_name = data.proxmox_virtual_environment_nodes.available_nodes.names[0]
}