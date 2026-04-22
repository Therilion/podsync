## Context

PodSync es una aplicación de salas colaborativas con frontend React, backend NestJS y comunicación en tiempo real. El TDD §4.2 fija el stack (TypeScript en ambos lados, NestJS+Fastify en el backend, React+Vite en el frontend, tipos compartidos vía paquete interno) y el TDD §11.1 prescribe organización monorepo. Este change materializa esa decisión arquitectónica como punto de partida del proyecto. No existe código previo más allá de documentación.

Restricciones: stack obligatorio (no sustituciones sin aprobación), almacenamiento de objetos vía SeaweedFS/S3 (no aplica en esta US pero se respeta el principio), Gitflow estricto con worktrees, Conventional Commits, metodología TDD (Red → Green → Refactor) en cada tarea con tests.

## Goals / Non-Goals

**Goals:**
- Establecer una raíz de monorepo con `pnpm` workspaces gestionado por Corepack y orquestado por Turborepo.
- Tres workspaces operativos: `apps/api` (NestJS+Fastify), `apps/web` (React+Vite+Tailwind) y `packages/shared` (tipos TS).
- Pipeline unificado: `pnpm dev` levanta web y api en paralelo con HMR; `pnpm build` compila respetando dependencias (`shared` antes de `api`/`web`); `pnpm test|lint|format` cubren todos los workspaces.
- TypeScript strict en toda la base con path alias `@podsync/shared` resoluble en runtime y build de cada workspace.
- TDD habilitado desde el día 1: Jest en api, Vitest en web, ambos con casos verde mínimos al cierre del change.

**Non-Goals:**
- Implementar dominio funcional (rooms, participants, signaling, chunks, persistencia). Sólo se exportan tipos placeholder para validar el cross-workspace.
- Configurar CI/CD, contenedores, despliegue, observabilidad o telemetría.
- Integrar SeaweedFS, base de datos, Redis o cualquier dependencia de infraestructura.
- Diseñar la UI o componentes reales más allá de un `App` mínimo.
- Husky/lint-staged: opcional; si se omite, no bloquea.

## Decisions

### Decisión 1: Turborepo sobre Nx u otros orquestadores
**Elección:** Turborepo.
**Razón:** El TDD lo prescribe explícitamente; ofrece pipeline declarativo, caché local + remota opcional y una huella mínima. Nx aporta más, pero introduce convenciones más invasivas y curva de aprendizaje innecesaria para 3 workspaces.
**Alternativas:** Nx (descartada por sobreingeniería), scripts npm puros (descartada por falta de cache/orden topológico).

### Decisión 2: pnpm fijado vía Corepack
**Elección:** `"packageManager": "pnpm@<latest-stable>"` en `package.json` raíz.
**Razón:** Corepack garantiza que cualquier desarrollador y CI usen exactamente la misma versión de pnpm sin instalación manual. pnpm ofrece store global, symlinks estrictos (evita phantom deps) y workspaces nativos.
**Alternativas:** npm workspaces (más lento, sin enforcement de boundaries), yarn berry (PnP introduce fricción con Vite/Vitest).

### Decisión 3: NestJS sobre Fastify (no Express)
**Elección:** `@nestjs/platform-fastify` con `FastifyAdapter`.
**Razón:** TDD §4.2 lo manda; Fastify ofrece mejor throughput y menor overhead, importante para WebSocket signaling y subida de chunks que vendrán en hitos posteriores.
**Alternativas:** Express (descartada: contradice TDD).

### Decisión 4: Vite + React 18+ con Tailwind 4 vía plugin oficial
**Elección:** Plugin `@tailwindcss/vite` y `@import "tailwindcss"` en CSS principal.
**Razón:** Tailwind 4 elimina el paso de PostCSS y la config JS verbosa; el plugin oficial Vite es la integración soportada upstream.
**Alternativas:** Tailwind 3 con PostCSS (config más antigua), CSS Modules (sin sistema de utilidades).

### Decisión 5: Path alias `@podsync/shared` resuelto vía workspace + `tsconfig.base.json`
**Elección:** `packages/shared` se publica como workspace `@podsync/shared` con `main: ./src/index.ts`; el alias en `tsconfig.base.json` apunta a `packages/shared/src` para que TypeScript resuelva tipos sin paso de build.
**Razón:** Permite consumo directo de TS sin pre-compilar shared en dev; Turborepo encadena builds de producción cuando hace falta.
**Alternativas:** Compilar shared a `dist` antes de consumir (más lento en dev, requiere watch mode adicional). El `moduleNameMapper` de Jest replica el alias para los tests del backend.

### Decisión 6: Jest en backend, Vitest en frontend
**Elección:** `ts-jest` para `apps/api`; `vitest` + `@testing-library/react` + `jsdom` para `apps/web`.
**Razón:** Jest es estándar en el ecosistema NestJS (su CLI lo asume). Vitest se integra nativamente con Vite y comparte su pipeline de transformación, evitando duplicar config.
**Alternativas:** Vitest en ambos (rompe convención NestJS, requiere ajustes para decoradores y reflect-metadata).

### Decisión 7: Proxy de Vite a `localhost:3000`
**Elección:** En `vite.config.ts` se redirigen `/api` (HTTP) y `/ws` (WebSocket con `ws:true`) a `http://localhost:3000`.
**Razón:** Evita CORS en desarrollo y permite que el frontend consuma rutas relativas que en producción servirá el mismo origen (o un reverse proxy).
**Alternativas:** CORS abierto en backend (peor postura de seguridad), variables de entorno con URLs absolutas (más fricción).

### Decisión 8: ESLint + Prettier centralizados, husky opcional
**Elección:** Configuración raíz con plugins TypeScript + react-hooks + import; Prettier con `singleQuote`, `trailingComma:'all'`, `printWidth:100`. Husky/lint-staged se incluyen como recomendación opcional, no bloqueante.
**Razón:** Reduce divergencia entre workspaces; husky se deja opcional para no imponer hooks a quien use entornos donde no funcionan bien (worktrees, contenedores).

## Risks / Trade-offs

- **[Riesgo]** Versión de pnpm/Node desactualizada al momento del setup → **Mitigación:** Documentar en README cómo refrescar `.nvmrc` y `packageManager` y verificar al inicio de cada sprint.
- **[Riesgo]** Tailwind 4 es relativamente nuevo y su API plugin puede romper en releases menores → **Mitigación:** Pinear a una versión exacta en `apps/web/package.json` y revalidar antes de actualizar.
- **[Riesgo]** El path alias resuelto a TS fuente puede causar problemas si `apps/api` se publica sin pre-compilar `shared` → **Mitigación:** Pipeline `build` de Turborepo declara `dependsOn: ^build`; `apps/api` consume `dist` de shared en producción vía resolución de workspace estándar.
- **[Trade-off]** Jest+Vitest duplica el toolchain de testing → **Mitigación:** Aceptado; cada uno alineado con su framework dominante reduce fricción mayor que la duplicación.
- **[Riesgo]** Olvido de habilitar Corepack en máquinas nuevas → **Mitigación:** Comando `corepack enable` documentado en README + script `preinstall` opcional que avise.
- **[Riesgo]** Configuración ESLint inconsistente entre workspaces → **Mitigación:** Una única config raíz que cada workspace extiende; no se permiten overrides locales sin justificación documentada.

## Migration Plan

No aplica — punto de partida del proyecto. Despliegue equivale a merge a `develop` tras revisión de PR.

## Open Questions

- ¿Adoptamos husky + lint-staged ahora o lo diferimos a una US posterior? Decisión sugerida: incluir como opcional en TASK-005 y dejar la decisión al equipo en review.
- ¿Necesitamos turbo remote cache (Vercel) ya o esperamos a tener CI? Decisión sugerida: esperar al hito de CI/CD.
