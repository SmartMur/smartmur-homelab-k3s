################################################################################
# k3s-worker-02  — Proxmox Host2 (192.168.100.200)
################################################################################

resource "proxmox_virtual_environment_vm" "k3s_worker02" {
  provider    = proxmox.pve2
  name        = "k3s-worker-02"
  description = "k3s worker node 2 — managed by Terraform"
  node_name   = "pve"

  tags = ["k3s", "worker"]

  clone {
    vm_id = var.vm_template_id_pve2
    full  = true
  }

  cpu {
    cores = var.worker_cpu
    type  = "host"
  }

  memory {
    dedicated = var.worker_ram_mb
  }

  disk {
    datastore_id = var.vm_storage_pool
    size         = var.worker_disk_gb
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.worker02_ip}/24"
        gateway = var.vm_gateway
      }
    }
    dns {
      servers = [var.vm_dns]
    }
    user_account {
      username = var.vm_user
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    ignore_changes = [initialization]
  }
}

################################################################################
# k3s-worker-03  — Proxmox Host2 (192.168.100.200)
################################################################################

resource "proxmox_virtual_environment_vm" "k3s_worker03" {
  provider    = proxmox.pve2
  name        = "k3s-worker-03"
  description = "k3s worker node 3 — managed by Terraform"
  node_name   = "pve"

  tags = ["k3s", "worker"]

  clone {
    vm_id = var.vm_template_id_pve2
    full  = true
  }

  cpu {
    cores = var.worker_cpu
    type  = "host"
  }

  memory {
    dedicated = var.worker_ram_mb
  }

  disk {
    datastore_id = var.vm_storage_pool
    size         = var.worker_disk_gb
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.worker03_ip}/24"
        gateway = var.vm_gateway
      }
    }
    dns {
      servers = [var.vm_dns]
    }
    user_account {
      username = var.vm_user
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    ignore_changes = [initialization]
  }
}
