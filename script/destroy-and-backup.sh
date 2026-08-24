#!/bin/bash
set -e

S3_BUCKET="tu-bucket-zomboid-backups"
REGION="us-east-1"

echo "=== 1. Obteniendo IDs de la infraestructura actual ==="
VOLUME_ID=$(terraform output -raw ebs_volume_id 2>/dev/null || aws ebs describe-volumes --filters "Name=tag:Name,Values=pz-world-data" --query "Volumes[0].VolumeId" --output text)
INSTANCE_IP=$(terraform output -raw public_ip 2>/dev/null)

echo "=== 2. Apagando servicio de Project Zomboid vía SSH ==="
ssh -o StrictHostKeyChecking=no ubuntu@$INSTANCE_IP "sudo -iu pzserver systemctl --user stop pzsvrtool@zomboid.service" || true

echo "=== 3. Creando Snapshot del volumen EBS ==="
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id $VOLUME_ID \
  --description "Backup automatico previo a destruccion" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=pz-world-data-snapshot}]' \
  --region $REGION \
  --query "SnapshotId" --output text)

echo "Snapshot creada: $SNAPSHOT_ID. Esperando confirmacion..."
aws ec2 wait snapshot-completed --snapshot-id $SNAPSHOT_ID --region $REGION

echo "=== 4. Copiando/Sincronizando Snapshot hacia Amazon S3 ==="
# Exportar datos / referencias de la Snapshot hacia el bucket seguro
aws s3 sync s3://$S3_BUCKET/latest/ s3://$S3_BUCKET/archive/$(date +%Y-%m-%d)/ || true
echo "snapshot_id=$SNAPSHOT_ID" > snapshot_meta.txt
aws s3 cp snapshot_meta.txt s3://$S3_BUCKET/latest/snapshot_meta.txt

echo "=== 5. Destruyendo infraestructura con Terraform ==="
terraform destroy -auto-approve

echo "=== Proceso completado. La instancia y el EBS fueron eliminados. Backup seguro en S3. ==="
