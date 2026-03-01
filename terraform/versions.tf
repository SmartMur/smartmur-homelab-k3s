terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73"
    }
  }
}

provider "proxmox" {
  # Host1 — used for master + worker-01
  # Override per-resource with alias "pve2" for Host2
  endpoint  = "https://${var.proxmox_host1_ip}:8006/"
  api_token = var.proxmox_api_token
  insecure  = true # self-signed cert in homelab
  ssh {
    agent    = true
    username = var.proxmox_ssh_user
  }
}

provider "proxmox" {
  alias     = "pve2"
  endpoint  = "https://${var.proxmox_host2_ip}:8006/"
  api_token = var.proxmox_api_token
  insecure  = true
  ssh {
    agent    = true
    username = var.proxmox_ssh_user
  }
}
