# server-bootstrap Specification

## Purpose
Define de dónde obtiene la instancia el código de configuración (repositorio y rama) que ejecuta en su primer arranque y en cada arranque de una instancia nueva.

## Requirements

### Requirement: Repositorio y rama configurables
El arranque DEBE (SHALL) clonar o actualizar el repositorio `repo_url` en la rama `repo_branch`, con valores por defecto el repositorio de GitHub del proyecto y `main`.

#### Scenario: Rama sin mergear
- **WHEN** se planifica con `repo_branch = "feat/x"`
- **THEN** el script de arranque clona y actualiza la rama `feat/x`

#### Scenario: Valores por defecto
- **WHEN** no se definen `repo_url` ni `repo_branch`
- **THEN** el script de arranque usa el repositorio del proyecto y la rama `main`

### Requirement: Rama válida
El stack DEBE (SHALL) rechazar en el plan un `repo_branch` con caracteres fuera de `[A-Za-z0-9._/-]`.

#### Scenario: Rama con caracteres inválidos
- **WHEN** `repo_branch = "main; rm -rf /"`
- **THEN** la planificación falla con un error de validación
