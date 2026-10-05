## MODIFIED Requirements

### Requirement: RAM suficiente verificada
El stack DEBE (SHALL) rechazar en el plan un tipo de instancia sin RAM nominal para el heap y el margen efectivos (del tier o de las variables) o que no sea x86_64, y el playbook DEBE (SHALL) rechazar un host cuya RAM utilizable (sin swap) no alcance.

#### Scenario: Instancia chica
- **WHEN** el tipo tiene menos RAM que heap + margen (por ejemplo, tier `robusto` con `instance_type = "m7i.large"`)
- **THEN** la planificación falla con un error que indica la RAM, el heap, el margen y el tier

#### Scenario: Valores por defecto
- **WHEN** se planifica con valores por defecto
- **THEN** el tier `estandar` (`m7i.large` con 4096 + 3072 MiB) es aceptado

## ADDED Requirements

### Requirement: Tiers de tamaño
El stack DEBE (SHALL) ofrecer los tiers `minimo`, `estandar` (por defecto), `robusto` y `grande`, cada uno con instancia, heap, margen y disco, DEBE (SHALL) permitir reemplazar cada valor con su variable y DEBE (SHALL) rechazar un tier desconocido.

#### Scenario: Tier robusto
- **WHEN** `tier = "robusto"`
- **THEN** la instancia es `r7i.large`, el heap 8192 MiB y el disco 50 GB

#### Scenario: Reemplazo de un valor
- **WHEN** `tier = "robusto"` y `root_volume_size_gb = 80`
- **THEN** el disco es de 80 GB y el resto sale del tier

#### Scenario: Tier desconocido
- **WHEN** `tier = "enorme"`
- **THEN** la planificación falla con un error de validación
