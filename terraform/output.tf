output "public_ip" {
  value       = aws_instance.pz_server.public_ip
  description = "IP Pública para conectarse al juego"
}

output "ebs_volume_id" {
  value       = aws_ebs_volume.pz_data_volume.id
  description = "ID del volumen EBS enlazado"
}
