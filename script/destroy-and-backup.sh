#!/bin/bash
set -e

S3_BUCKET="tu-bucket-zomboid-backups"
REGION="us-east-1"

echo "=== 1. Obteniendo IDs de la infraestructura actual ==="
INSTANCE_IP=$(terraform output -raw public_ip 2>/dev/null)

# Obtener el Volume ID del DISCO RAÍZ único asignado a la EC2
VOLUME_ID=$(aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=pz-world-data-root" \
  --query "Volumes[0].VolumeId" --output text --region $REGION)

if [ -z "$VOLUME_ID" ] || [ "$VOLUME_ID" == "None" ]; then
  echo "Error: No se encontró el disco raíz con el tag 'pz-world-data-root'."
  exit 1
fi

echo "=== 2. Apagando servicio de Project Zomboid vía SSH ==="
ssh -o StrictHostKeyChecking=no ubuntu@$INSTANCE_IP "sudo -iu pzserver systemctl --user stop pzsvrtool@zomboid.service" || true

echo "=== 3. Creando Snapshot del disco único de 30 GB ==="
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id $VOLUME_ID \
  --description "Backup completo de EC2 previo a destruccion" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=pz-world-data-snapshot}]' \
  --region $REGION \
  --query "SnapshotId" --output text)

echo "Snapshot creada: $SNAPSHOT_ID. Esperando confirmación..."
aws ec2 wait snapshot-completed --snapshot-id $SNAPSHOT_ID --region $REGION

echo "=== 4. Guardando metadatos en Amazon S3 ==="
aws s3 sync s3://$S3_BUCKET/latest/ s3://$S3_BUCKET/archive/$(date +%Y-%m-%d)/ || true
echo "snapshot_id=$SNAPSHOT_ID" > snapshot_meta.txt
aws s3 cp snapshot_meta.txt s3://$S3_BUCKET/latest/snapshot_meta.txt

echo "=== 5. Destruyendo infraestructura con Terraform ==="
terraform destroy -auto-approve

echo "=== Proceso completado. La instancia y su disco fueron eliminados. Snapshot guardada en AWS. ==="
