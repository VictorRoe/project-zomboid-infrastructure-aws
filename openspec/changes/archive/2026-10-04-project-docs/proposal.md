# Proposal

## Por qué

El repositorio tiene un README de una sola línea y ningún registro de cómo encajan las piezas ni de por qué se construyeron así. Los cinco cambios de corrección (issues #1–#5) necesitan un lugar donde registrar el estado actual y las decisiones, y el proyecto necesita un changelog para mantener legibles los lanzamientos.

## Qué cambia

- Agregar `docs/` según la convención establecida por el mantenedor:
  - `docs/architecture.md` — componentes, recursos de AWS, estructura en el host, diagrama.
  - `docs/flows.md` — flujos de aprovisionamiento, respaldo y destrucción, actualización automática, (más adelante) restauración y pruebas.
  - `docs/spec.md` — estado objetivo actual (variables, puertos, rutas, servicios).
  - `docs/decisions.md` — registro de decisiones numeradas y fechadas (D1…), cada una con su motivo y sus consecuencias; inicializado con las decisiones de diseño existentes inferidas del código.
  - `docs/operations.md` — comandos del día a día.
- Agregar `CHANGELOG.md` (formato Keep a Changelog, sección `[Unreleased]`).
- Confirmar (commit) `CLAUDE.md`; ampliar el README a una descripción breve que enlace a `docs/`.
- Cada cambio posterior actualiza `docs/spec.md`, agrega una entrada a `docs/decisions.md` y agrega una entrada a `CHANGELOG.md`.

## Capacidades

### Capacidades nuevas

### Capacidades modificadas

Sin cambios de comportamiento — solo documentación (`skip_specs: true`).

## Impacto

Solo documentación: `docs/`, `README.md`, `CHANGELOG.md`, `CLAUDE.md`. Base de la pila de ramas para los cinco cambios de corrección.
