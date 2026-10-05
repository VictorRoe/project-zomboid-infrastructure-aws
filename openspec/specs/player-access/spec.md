# player-access Specification

## Purpose
Restringe el ingreso de jugadores con una contraseña gestionada, persistente y distinta de la de administrador, sin exponerla fuera del host.

## Requirements

### Requirement: Contraseña de ingreso gestionada
El aprovisionamiento DEBE (SHALL) asegurar una contraseña de ingreso (provista o generada aleatoriamente), persistida con permisos restrictivos, distinta de la de administrador, y escrita en `Password=` antes de que el juego admita jugadores.

#### Scenario: Primera ejecución
- **WHEN** no se provee `pz_join_password`
- **THEN** se genera una de 24 caracteres en `.join_password` (0600) y el `.ini` la contiene antes del primer arranque

#### Scenario: Igual a la de admin
- **WHEN** `pz_join_password` es igual a `pz_admin_password`
- **THEN** la ejecución falla antes de escribir nada

### Requirement: Persistencia y rotación
La contraseña de ingreso DEBE (SHALL) reutilizarse en re-ejecuciones y restauraciones, y DEBE (SHALL) regenerarse solo con `pz_join_password_rotate` o un valor provisto, aplicándola con un reinicio ordenado.

#### Scenario: Rotación
- **WHEN** se ejecuta con `pz_join_password_rotate=true`
- **THEN** hay una contraseña nueva y el `.ini` la contiene

### Requirement: Higiene de la contraseña de ingreso
La contraseña de ingreso NO DEBE (SHALL NOT) aparecer en la salida de las tareas, el estado de Terraform, el `user_data` ni Git.

#### Scenario: Salida del playbook
- **WHEN** se genera o aplica la contraseña
- **THEN** su valor no aparece en la salida
