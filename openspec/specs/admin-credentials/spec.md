# admin-credentials Specification

## Purpose
Garantiza que cada servidor de Project Zomboid aprovisionado tenga una contraseña de administrador root robusta y persistente, que nunca sea un valor por defecto compartido.

## Requirements

### Requirement: Sin contraseña de administrador por defecto
El aprovisionamiento NO DEBE (SHALL NOT) configurar una contraseña de administrador fija por defecto. Cuando no se suministre una contraseña, se DEBE (SHALL) generar una contraseña aleatoria de al menos 24 caracteres alfanuméricos.

#### Scenario: Primera ejecución desatendida
- **WHEN** el playbook se ejecuta sin `pz_admin_password`
- **THEN** se genera una contraseña aleatoria, se escribe en el archivo de contraseña de administrador con modo 0600 y propietario el usuario del servidor, y se usa en la configuración de pzsvrtool

### Requirement: La contraseña generada persiste
Una contraseña generada previamente se DEBE (SHALL) reutilizar en las ejecuciones posteriores en lugar de regenerarse.

#### Scenario: Nueva ejecución sobre un disco restaurado
- **WHEN** el archivo de contraseña de administrador ya existe y no se suministra ninguna contraseña
- **THEN** se usa la contraseña existente sin cambios

### Requirement: Robustez de la contraseña suministrada
Una contraseña suministrada se DEBE (SHALL) rechazar, haciendo fallar la ejecución antes de cualquier cambio en el host, si tiene menos de 12 caracteres, coincide con un valor débil conocido, o contiene espacios en blanco o `=`.

#### Scenario: Valor débil
- **WHEN** se suministra `pz_admin_password=test`
- **THEN** la ejecución falla durante la validación con un mensaje que explica la regla

#### Scenario: Valor robusto
- **WHEN** se suministra una contraseña de 16 caracteres sin espacios en blanco ni `=`
- **THEN** la validación pasa y esa contraseña se usa y se escribe en el archivo de contraseña de administrador

### Requirement: Higiene de secretos
La contraseña de administrador NO DEBE (SHALL NOT) aparecer en la salida de las tareas, en el estado de Terraform ni en los datos de usuario de la instancia.

#### Scenario: Salida de registros
- **WHEN** el playbook se ejecuta con la verbosidad por defecto
- **THEN** ninguna salida de tarea contiene el valor de la contraseña
