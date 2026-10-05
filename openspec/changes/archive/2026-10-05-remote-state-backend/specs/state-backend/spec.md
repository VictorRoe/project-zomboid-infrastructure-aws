## ADDED Requirements

### Requirement: Estado remoto con bloqueo
El stack DEBE (SHALL) guardar su estado en S3 con cifrado y bloqueo nativo, con bucket y región provistos fuera del repositorio.

#### Scenario: Configuración del backend
- **WHEN** se inspecciona `terraform/backend.tf`
- **THEN** usa `backend "s3"` con `encrypt` y `use_lockfile` y sin bucket hardcodeado

### Requirement: Bucket del estado seguro e independiente
El bucket del estado DEBE (SHALL) crearse en un stack separado, con versionado, cifrado en reposo, acceso público bloqueado, rechazo de accesos sin TLS y protección contra destrucción, y DEBE (SHALL) conservar las versiones anteriores al menos 7 días.

#### Scenario: Valores por defecto seguros
- **WHEN** se aplica `bootstrap/state-backend` con valores por defecto
- **THEN** el bucket `pz-tfstate-<cuenta>-<región>` tiene versionado, AES256, acceso público bloqueado y una política que niega `aws:SecureTransport = false`

#### Scenario: Retención demasiado corta
- **WHEN** `noncurrent_version_days = 1`
- **THEN** la planificación falla con un error de validación
