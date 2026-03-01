output "k3s_master_ip" {
  description = "k3s master node IP"
  value       = var.master_ip
}

output "k3s_worker_ips" {
  description = "k3s worker node IPs"
  value = [
    var.worker01_ip,
    var.worker02_ip,
    var.worker03_ip,
  ]
}

output "cluster_summary" {
  description = "Quick-reference cluster layout"
  value = <<-EOT
    k3s Cluster Layout
    ──────────────────────────────────────────────
    Master  : k3s-master-01  @ ${var.master_ip}   (pve1: ${var.proxmox_host1_ip})
    Worker1 : k3s-worker-01  @ ${var.worker01_ip}  (pve1: ${var.proxmox_host1_ip})
    Worker2 : k3s-worker-02  @ ${var.worker02_ip}  (pve2: ${var.proxmox_host2_ip})
    Worker3 : k3s-worker-03  @ ${var.worker03_ip}  (pve2: ${var.proxmox_host2_ip})
    ──────────────────────────────────────────────
    Kubeconfig: scp ubuntu@${var.master_ip}:~/.kube/config ~/.kube/config
  EOT
}

output "ansible_inventory_hint" {
  description = "Paste into ansible/inventory.yml after provisioning"
  value = <<-EOT
    k3s_master: ${var.master_ip}
    k3s_workers:
      - ${var.worker01_ip}
      - ${var.worker02_ip}
      - ${var.worker03_ip}
  EOT
}
