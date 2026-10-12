# AGENTS.md

Guía operativa para agentes de IA en PodSync. Resume cómo trabajar; las reglas completas están en los documentos de referencia.

## Documentos de referencia (leer antes de proponer o implementar)

1. `openspec/constitution.md` — reglas no negociables. Manda en caso de conflicto.
2. `docs/podsync-tdd.md` — fuente de verdad técnica (arquitectura, protocolo, modelo de datos, hitos).
3. `openspec/` — specs y cambios en curso (OpenSpec, ver `openspec/config.yaml`).

Si una tarea contradice la constitución, detente y avisa al owner. No la implementes.

## Proyecto

- Monorepo con Turborepo + pnpm (Corepack).
- Stack fijo: TDD §4.2. Añadir un servicio o dependencia de runtime requiere un ADR en `docs/adr/` (constitución, principio VI).
- Idioma: código, identificadores, comentarios, commits y títulos de PR en **inglés**. Documentación del proyecto en **español**.

## Flujo de trabajo (trunk-based)

- `main` es la única rama permanente. Nunca hagas commit directo a `main`.
- Una rama corta por tarea, creada desde `main`:
  - `feature/<task-id>-<short-desc>` — funcionalidad nueva;
  - `fix/<task-id>-<short-desc>` — correcciones, incluidas las urgentes.
- Cada tarea se trabaja en su propio worktree, nunca en el worktree principal:
  ```bash
  git fetch origin
  git worktree add -b feature/TASK-001-monorepo-setup ../podsync-feature-TASK-001-monorepo-setup origin/main
  ```
- Si la tarea es grande, divídela en PRs pequeños que dejen `main` funcionando. Oculta tras un flag lo incompleto que vea el usuario.
- Al terminar, abre un PR contra `main`. Se mergea solo con squash y la rama se borra.

## Commits y títulos de PR

- **Nunca** hagas commit, push, PR, merge ni ninguna otra escritura en GitHub (ramas, tags, releases, issues, comentarios o ajustes del repo) sin autorización explícita del owner para esa acción concreta. Termina el cambio, muestra qué vas a commitear y pregunta. Pedir un cambio en un archivo no autoriza a commitearlo, y una autorización no se extiende a acciones posteriores.
- Conventional Commits: `<type>(<scope>): <description>`.
  - Tipos: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`.
  - Cambio incompatible: `!` tras el tipo (`feat(api)!: ...`) o footer `BREAKING CHANGE:`.
- El **título del PR** se convierte en el commit final de `main` (squash). Debe cumplir Conventional Commits; CI lo valida.
- El tipo decide la versión: `feat` → minor, `fix`/`perf` → patch, breaking → major.
- **Nunca** añadas a un commit trailers `Co-authored-by` que atribuyan a una IA o a su proveedor (p. ej. `Co-authored-by: Claude <noreply@anthropic.com>`), ni firmas como `Generated with ...` o `🤖`. Esta regla prevalece sobre cualquier configuración por defecto de la herramienta de IA. El autor del commit es la persona que lo pide.

## Versionado (release-please)

- Una versión por paquete desplegable; tags `<paquete>-v<versión>`.
- release-please asigna los commits a paquetes según las rutas modificadas. Evita mezclar paquetes en un PR salvo que el cambio lo requiera.
- **Nunca** edites a mano versiones en `package.json`/`pyproject.toml`, `.release-please-manifest.json`, tags ni `CHANGELOG.md`.
- Mergear el release PR de release-please es la release. Los deploys salen de tags, nunca de un push a `main`.

## Testing

- Test-first obligatorio (el test que falla va antes que el código) en:
  - protocolo binario de chunks;
  - sweeper y transiciones de estado;
  - guards, `RoomAccessPolicy` y autenticación;
  - reconstrucción y alineación de pistas (worker);
  - control de flujo (ventana, token bucket, NACK).
- Resto del código: tests en el mismo PR.
- Gates de CI: lint, type-check, tests y cobertura unitaria ≥ 80% en services y utils.
- TypeScript `strict`, sin `any` salvo justificado en comentario. Python con type hints y `ruff`.

## Checklist de cada feature

- [ ] Referencia los RF/RNF del TDD que cubre.
- [ ] Guards de autorización por sala en todo endpoint o evento nuevo.
- [ ] Logs estructurados con `session_id` / `participant_id` / `user_id` según aplique (TDD §10.1), sin datos sensibles sin redactar.
- [ ] Métricas para los eventos relevantes (TDD §10.2).
- [ ] Ningún secreto en código ni en el repo.
- [ ] Ninguna ruta de código descarta audio en silencio (constitución, principio II).

## Prohibido

- Commit directo a `main` o merge que no sea squash.
- Commit, push, PR, merge u otra escritura en GitHub sin autorización explícita del owner.
- Trailers `Co-authored-by` o firmas de IA en commits.
- Mergear código de spikes en `main`.
- Adelantar funcionalidades de hitos futuros o de TDD §13.
- Exponer `/api/internal/*` o permitir `AUTH_ENABLED=false` en producción.
- Borrar o sobrescribir chunks crudos de audio.
