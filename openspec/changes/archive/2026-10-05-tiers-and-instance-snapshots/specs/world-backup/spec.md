## MODIFIED Requirements

### Requirement: Snapshots automáticos con retención
Salvo que se desactive, la propia instancia DEBE (SHALL) hacer un snapshot automático de su disco del mundo una vez por día y solo mientras está prendida (a la hora configurada o, si estaba apagada, al prender), y DEBE (SHALL) conservar los `backup_retain_count` más nuevos borrando solo snapshots automáticos completados de su servidor.

#### Scenario: Valores por defecto
- **WHEN** se planifica con valores por defecto
- **THEN** la instancia recibe un timer diario a las 09:00 UTC que conserva 4 snapshots automáticos, y un rol que solo puede crear snapshots del volumen con `pz-world-volume=<nombre>` y borrar los `pz-backup=auto` de su servidor

#### Scenario: Rotación
- **WHEN** hay 6 automáticos y se crea uno nuevo con retención 4
- **THEN** se borran los 3 más viejos y ningún snapshot manual ni de otro servidor

#### Scenario: Snapshot reciente
- **WHEN** el último automático tiene menos de 12 horas
- **THEN** no se crea otro

#### Scenario: Fuera de EC2
- **WHEN** no hay metadatos de instancia (VM local)
- **THEN** el script termina sin hacer nada
