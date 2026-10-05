output "public_ip" {
  value       = aws_eip.pz.public_ip
  description = "IP pública estable (Elastic IP) para conectarse al juego y por SSH"
}

output "instance_id" {
  value       = aws_instance.pz_server.id
  description = "ID de la EC2 (lo usa script/pz-ctl.sh para start/stop)"
}

output "root_volume_id" {
  value       = aws_instance.pz_server.root_block_device[0].volume_id
  description = "ID del disco único EBS (Root Volume)"
}

output "restored_from_snapshot_id" {
  value       = local.restore_snapshot_id
  description = "Snapshot desde el que se restauró el disco (vacío = instalación nueva)"
}

output "aws_region" {
  value       = var.aws_region
  description = "Región de AWS del stack"
}

output "pz_server_name" {
  value       = var.pz_server_name
  description = "Nombre del servidor de Project Zomboid"
}

output "repo_commit" {
  value       = var.repo_follow_branch ? "" : var.repo_commit
  description = "Commit fijo que ejecuta la instancia (vacío = modo de prueba que sigue repo_branch)"
}

output "ssh_enabled" {
  value       = local.ssh_enabled
  description = "true si hay key pair y redes administrativas para SSH"
}

output "tier" {
  value = {
    tier             = var.tier
    instance_type    = local.instance_type
    java_xmx_mb      = local.java_xmx_mb
    host_overhead_mb = local.host_overhead_mb
    disk_gb          = local.root_volume_size
  }
  description = "Perfil de tamaño efectivo (tier más las variables que lo reemplazan)"
}

output "auto_backup" {
  value       = var.auto_backup_enabled ? "diario a las ${var.backup_time_utc} UTC con la instancia prendida; se conservan ${var.backup_retain_count}" : "desactivado"
  description = "Snapshots automáticos"
}
