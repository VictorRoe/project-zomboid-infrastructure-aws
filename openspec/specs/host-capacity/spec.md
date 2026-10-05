# host-capacity Specification

## Purpose
Garantiza que la instancia y el heap de Java del servidor sean coherentes: RAM suficiente verificada antes de crear y en el host, aviso de CPU burstable y heap gestionado.

## Requirements

### Requirement: RAM suficiente verificada
El stack DEBE (SHALL) rechazar en el plan un tipo de instancia sin RAM nominal para el heap y el margen efectivos (del tier o de las variables) o que no sea x86_64, y el playbook DEBE (SHALL) rechazar un host cuya RAM utilizable (sin swap) no alcance.

#### Scenario: Instancia chica
- **WHEN** el tipo tiene menos RAM que heap + margen (por ejemplo, tier `robusto` con `instance_type = "m7i.large"`)
- **THEN** la planificación falla con un error que indica la RAM, el heap, el margen y el tier

#### Scenario: Valores por defecto
- **WHEN** se planifica con valores por defecto
- **THEN** el tier `estandar` (`m7i.large` con 5632 + 1536 MiB) es aceptado

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

### Requirement: Tiers de tamaño
El stack DEBE (SHALL) ofrecer los tiers `minimo`, `estandar` (por defecto), `robusto` y `grande`, cada uno con instancia, heap, margen (creciente con el tier) y disco, DEBE (SHALL) permitir reemplazar cada valor con su variable y DEBE (SHALL) rechazar un tier desconocido.

#### Scenario: Tier robusto
- **WHEN** `tier = "robusto"`
- **THEN** la instancia es `r7i.large`, el heap 13312 MiB, el margen 2048 MiB y el disco 50 GB

#### Scenario: Reemplazo de un valor
- **WHEN** `tier = "robusto"` y `root_volume_size_gb = 80`
- **THEN** el disco es de 80 GB y el resto sale del tier

#### Scenario: Tier desconocido
- **WHEN** `tier = "enorme"`
- **THEN** la planificación falla con un error de validación
