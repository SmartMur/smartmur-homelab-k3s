################################################################################
# Proxmox Connection
################################################################################

variable "proxmox_host1_ip" {
  description = "Proxmox Host1 IP address"
  type        = string
  default     = "192.168.100.100"
}

variable "proxmox_host2_ip" {
  description = "Proxmox Host2 IP address"
  type        = string
  default     = "192.168.100.200"
}

variable "proxmox_api_token" {
  description = "Proxmox API token — format: user@realm!tokenid=secret"
  type        = string
  sensitive   = true
  # Set via: export TF_VAR_proxmox_api_token='root@pam!terraform=<uuid>'
}

variable "proxmox_ssh_user" {
  description = "SSH user for Proxmox hosts (for cloud-init image upload)"
  type        = string
  default     = "root"
}

################################################################################
# VM Common
################################################################################

variable "vm_template_id" {
  description = "Template ID on PVE1/alpha (9001 = Debian 12)"
  type        = number
  default     = 9001
}

variable "vm_template_id_pve2" {
  description = "Template ID on PVE2/pve (9002 = Debian 12 copy). PVE1+PVE2 share VM ID namespace — each node needs its own template."
  type        = number
  default     = 9002
}

variable "vm_storage_pool" {
  description = "Proxmox storage pool for VM disks (e.g. local-lvm, local-zfs)"
  type        = string
  default     = "local-lvm"
}

variable "vm_network_bridge" {
  description = "Proxmox network bridge (e.g. vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "vm_gateway" {
  description = "Default gateway for VM network"
  type        = string
  default     = "192.168.100.1"
}

variable "vm_dns" {
  description = "DNS server for VMs"
  type        = string
  default     = "192.168.100.1"
}

variable "ssh_public_key" {
  description = "SSH public key to inject into VMs via cloud-init"
  type        = string
  # Set via: export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
}

variable "vm_user" {
  description = "Default VM user created by cloud-init. ubuntu (template 9000) or debian (template 9001)"
  type        = string
  default     = "debian"
}

################################################################################
# k3s Node Specs
################################################################################

variable "master_cpu" {
  type    = number
  default = 2
}
variable "master_ram_mb" {
  type    = number
  default = 4096
}
variable "master_disk_gb" {
  type    = number
  default = 40
}

variable "worker_cpu" {
  type    = number
  default = 2
}
variable "worker_ram_mb" {
  type    = number
  default = 4096
}
variable "worker_disk_gb" {
  type    = number
  default = 40
}

################################################################################
# Network IP Assignments
################################################################################

variable "master_ip" {
  type    = string
  default = "192.168.100.110"
}
variable "worker01_ip" {
  type    = string
  default = "192.168.100.111"
}
variable "worker02_ip" {
  type    = string
  default = "192.168.100.112"
}
variable "worker03_ip" {
  type    = string
  default = "192.168.100.113"
}
