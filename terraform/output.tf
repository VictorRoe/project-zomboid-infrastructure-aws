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

output "backup_policy_id" {
  value       = var.backup_policy_enabled ? aws_dlm_lifecycle_policy.world[0].id : ""
  description = "Política DLM de snapshots automáticos (vacío = desactivada)"
}
