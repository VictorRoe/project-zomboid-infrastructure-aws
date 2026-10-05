## MODIFIED Requirements

### Requirement: Repositorio y rama configurables
El arranque DEBE (SHALL) obtener del repositorio `repo_url` el commit exacto `repo_commit` (alcanzable desde `repo_branch` o por SHA), y DEBE (SHALL) seguir la punta de `repo_branch` solo cuando `repo_follow_branch` es verdadero, como modo de prueba explícito. Valores por defecto: el repositorio de GitHub del proyecto y la rama `main`.

#### Scenario: Valores por defecto
- **WHEN** no se definen `repo_url` ni `repo_branch` y `repo_commit` es un SHA de 40 caracteres
- **THEN** el `user_data` configura el repositorio del proyecto, la rama `main`, ese commit y `repo_follow_branch = false`

#### Scenario: Rama sin mergear
- **WHEN** se planifica con `repo_follow_branch = true`, `repo_commit = ""` y `repo_branch = "feat/x"`
- **THEN** el arranque usa la punta de `feat/x` y lo advierte como mutable

## ADDED Requirements

### Requirement: Revisión exacta obligatoria
El stack DEBE (SHALL) rechazar en el plan un `repo_commit` que no sea un SHA completo de 40 caracteres hexadecimales en minúscula, salvo en modo rama, y DEBE (SHALL) rechazar que se definan ambos.

#### Scenario: Sin commit
- **WHEN** `repo_commit = ""` y `repo_follow_branch = false`
- **THEN** la planificación falla con un error de validación

#### Scenario: SHA abreviado
- **WHEN** `repo_commit = "ABCDEF1"`
- **THEN** la planificación falla con un error de validación

### Requirement: HEAD verificado sin fallback
Antes de ejecutar Ansible, el arranque DEBE (SHALL) verificar que `HEAD` es el commit pedido; si el commit no existe o no coincide, DEBE (SHALL) abortar sin ejecutar el playbook ni usar otra revisión.

#### Scenario: Commit inexistente
- **WHEN** `repo_commit` no existe en el repositorio
- **THEN** el arranque sale con error y el playbook no se ejecuta

#### Scenario: Disco restaurado
- **WHEN** el checkout ya existe en otra revisión y con cambios locales
- **THEN** queda en el commit pedido, descartando los cambios, antes del playbook

### Requirement: Actualización deliberada
Un cambio de `repo_commit` NO DEBE (SHALL NOT) modificar una instancia existente; la actualización de un host en marcha DEBE (SHALL) hacerse explícitamente con `pz-provision --commit`, que registra el commit nuevo solo si el playbook termina bien.

#### Scenario: Commit nuevo con un servidor en marcha
- **WHEN** se planifica otro `repo_commit` sobre una instancia existente
- **THEN** la instancia no cambia y el output `repo_commit` refleja el nuevo valor

#### Scenario: Playbook fallido
- **WHEN** `pz-provision --commit <sha>` falla en el playbook
- **THEN** el commit registrado sigue siendo el anterior
