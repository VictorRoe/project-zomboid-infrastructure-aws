# Spec Delta

## Purpose

Asegura que todo servidor de Project Zomboid aprovisionado tenga una contraseña de administrador root robusta y persistente que nunca sea un valor por defecto compartido.

## ADDED Requirements

### Requirement: Sin contraseña de administrador por defecto
El aprovisionamiento NO DEBE (SHALL NOT) configurar una contraseña de administrador por defecto fija. Cuando no se proporcione contraseña, DEBE (SHALL) generarse una contraseña aleatoria de al menos 24 caracteres alfanuméricos.

#### Scenario: Primera ejecución sin supervisión
- **WHEN** el playbook se ejecuta sin `pz_admin_password`
- **THEN** se genera una contraseña aleatoria, se escribe en el archivo de contraseña de administrador con modo 0600 y propiedad del usuario del servidor, y se usa en la configuración de pzsvrtool

### Requirement: La contraseña generada persiste
Una contraseña generada previamente DEBE (SHALL) reutilizarse en ejecuciones posteriores en lugar de regenerarse.

#### Scenario: Nueva ejecución sobre un disco restaurado
- **WHEN** el archivo de contraseña de administrador ya existe y no se proporciona contraseña
- **THEN** se usa la contraseña existente sin cambios

### Requirement: Robustez de la contraseña proporcionada
Una contraseña proporcionada DEBE (SHALL) ser rechazada, haciendo fallar la ejecución antes de cualquier cambio en el host, si tiene menos de 12 caracteres, coincide con un valor débil conocido o contiene espacios en blanco o `=`.

#### Scenario: Valor débil
- **WHEN** se proporciona `pz_admin_password=test`
- **THEN** la ejecución falla durante la validación con un mensaje que explica la regla

#### Scenario: Valor robusto
- **WHEN** se proporciona una contraseña de 16 caracteres sin espacios en blanco ni `=`
- **THEN** la validación pasa y se usa esa contraseña, que se escribe en el archivo de contraseña de administrador

### Requirement: Higiene de secretos
La contraseña de administrador NO DEBE (SHALL NOT) aparecer en la salida de tareas, en el estado de Terraform ni en el user data de la instancia.

#### Scenario: Salida de logs
- **WHEN** el playbook se ejecuta con verbosidad por defecto
- **THEN** ninguna salida de tareas contiene el valor de la contraseña
