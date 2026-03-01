################################################################################
# k3s-master-01  — Proxmox Host1 (192.168.100.100)
################################################################################

resource "proxmox_virtual_environment_vm" "k3s_master" {
  name        = "k3s-master-01"
  description = "k3s control plane — managed by Terraform"
  node_name   = "alpha"

  tags = ["k3s", "master"]

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  cpu {
    cores   = var.master_cpu
    type    = "host"
  }

  memory {
    dedicated = var.master_ram_mb
  }

  disk {
    datastore_id = var.vm_storage_pool
    size         = var.master_disk_gb
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
        address = "${var.master_ip}/24"
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
# k3s-worker-01  — Proxmox Host1 (192.168.100.100)
################################################################################

resource "proxmox_virtual_environment_vm" "k3s_worker01" {
  name        = "k3s-worker-01"
  description = "k3s worker node 1 — managed by Terraform"
  node_name   = "alpha"

  tags = ["k3s", "worker"]

  clone {
    vm_id = var.vm_template_id
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
        address = "${var.worker01_ip}/24"
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
