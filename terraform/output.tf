output "public_ip" {
  value       = aws_instance.pz_server.public_ip
  description = "IP Pública para conectarse al juego"
}

output "root_volume_id" {
  value       = aws_instance.pz_server.root_block_device[0].volume_id
  description = "ID del disco único EBS (Root Volume)"
}
