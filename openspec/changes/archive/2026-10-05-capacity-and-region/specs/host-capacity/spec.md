## ADDED Requirements

### Requirement: RAM suficiente verificada
El stack DEBE (SHALL) rechazar en el plan un tipo de instancia sin RAM nominal para `pz_java_xmx_mb` + `pz_host_overhead_mb` o que no sea x86_64, y el playbook DEBE (SHALL) rechazar un host cuya RAM utilizable (sin swap) no alcance.

#### Scenario: Instancia chica
- **WHEN** el tipo tiene 4096 MiB y el perfil necesita 7168
- **THEN** la planificación falla con un error que indica ambos valores

#### Scenario: Valores por defecto
- **WHEN** se planifica con valores por defecto
- **THEN** `m7i.large` con 4096 + 3072 MiB es aceptado

### Requirement: Aviso de CPU burstable
El plan DEBE (SHALL) advertir cuando el tipo de instancia es de CPU burstable.

#### Scenario: t3.large
- **WHEN** `instance_type = "t3.large"`
- **THEN** el check `burstable_cpu` falla como advertencia

### Requirement: Heap gestionado
El aprovisionamiento DEBE (SHALL) fijar `-Xmx<pz_java_xmx_mb>m` en `ProjectZomboid64.json`, bajar un `-Xms` mayor y volver a fijarlo después de cada actualización del juego.

#### Scenario: Heap distinto
- **WHEN** el JSON tiene `-Xmx4g` y `-Xms6g` y el valor es 4096
- **THEN** queda `-Xmx4096m` y `-Xms4096m`, y se pide detener el juego si corría
