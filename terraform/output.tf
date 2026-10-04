output "public_ip" {
  value       = aws_instance.pz_server.public_ip
  description = "IP Pública para conectarse al juego"
}

output "root_volume_id" {
  value       = aws_instance.pz_server.root_block_device[0].volume_id
  description = "ID del disco único EBS (Root Volume)"
}

output "restored_from_snapshot_id" {
  value       = local.restore_snapshot_id
  description = "Snapshot desde el que se restauró el disco (vacío = instalación nueva)"
}
