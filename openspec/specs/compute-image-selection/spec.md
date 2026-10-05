# compute-image-selection Specification

## Purpose
Define cómo se selecciona la imagen de máquina del servidor de Project Zomboid para que el stack se despliegue en cualquier región de AWS sin editar código.

## Requirements

### Requirement: Imagen por defecto resuelta por región
Cuando no se suministra una imagen explícita, el stack DEBE (SHALL) usar la imagen Canonical Ubuntu Server LTS x86_64 (hvm, gp3/ebs) más reciente disponible en la `aws_region` configurada.

#### Scenario: Búsqueda por defecto
- **WHEN** se planifica el stack sin `ami_id` y la búsqueda de la imagen de Ubuntu devuelve `ami-lookup123`
- **THEN** la instancia usa `ami-lookup123`

### Requirement: Imagen explícita
El stack DEBE (SHALL) aceptar una entrada opcional `ami_id`; cuando no esté vacía y no aplique una restauración del mundo, la instancia DEBE (SHALL) usar exactamente esa imagen y se DEBE (SHALL) ignorar el resultado de la búsqueda.

#### Scenario: Imagen explícita suministrada
- **WHEN** se planifica el stack con `ami_id = "ami-override123"`
- **THEN** la imagen de la instancia es `ami-override123`

### Requirement: Verificación sin conexión
El comportamiento de selección de imagen DEBE (SHALL) poder verificarse con proveedores simulados (mocks), sin requerir credenciales de AWS ni llamadas de red a las APIs de AWS.

#### Scenario: Las pruebas se ejecutan sin credenciales
- **WHEN** `make test` se ejecuta sin credenciales de AWS configuradas
- **THEN** las pruebas de selección de imagen se ejecutan y pasan

### Requirement: Sin reemplazo implícito ante un cambio de imagen
Un cambio en la imagen resuelta NO DEBE (SHALL NOT) reemplazar una instancia de servidor existente; el reemplazo DEBE (SHALL) ocurrir solo cuando se solicite explícitamente.

#### Scenario: Se publica una imagen más nueva
- **WHEN** la instancia existe y la búsqueda luego resuelve un ID de imagen distinto
- **THEN** el plan no muestra ningún reemplazo de la instancia

### Requirement: Ubicación coherente con la región
La zona de disponibilidad DEBE (SHALL) tomar por defecto una elegida por AWS dentro de `aws_region`, y una zona definida explícitamente fuera de esa región DEBE (SHALL) rechazarse en el momento del plan.

#### Scenario: Zona que no coincide
- **WHEN** `aws_region = "sa-east-1"` y `availability_zone = "us-east-1a"`
- **THEN** la planificación falla con un error de validación
