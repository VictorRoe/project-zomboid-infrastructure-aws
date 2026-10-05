# Spec Delta

## ADDED Requirements

### Requirement: Puerto SSH configurable
El procedimiento de backup DEBE (SHALL) usar el puerto SSH indicado en `SSH_PORT`, o el 22 si no está definido.

#### Scenario: Puerto personalizado
- **WHEN** se ejecuta con `SSH_PORT=2222`
- **THEN** todas las conexiones SSH usan el puerto 2222
