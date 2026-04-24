## Why

PodSync arranca sin código de aplicación: el repositorio actual sólo contiene documentación. Para habilitar el desarrollo paralelo de frontend, backend y tipos compartidos definidos en el TDD (§4.2), necesitamos una base de monorepo unificada que asegure builds reproducibles, pipeline de tareas consistente y consumo cross-workspace sin fricción. Esta es la US fundacional del Hito 1 (US-001) y bloquea cualquier otra historia hasta completarse.

## What Changes

- Inicializar monorepo con Turborepo + pnpm workspaces fijado vía Corepack en el `package.json` raíz.
- Crear `tsconfig.base.json` con strict mode, `module: ESNext`, `moduleResolution: bundler` y path alias `@podsync/shared` → `packages/shared/src`.
- Crear workspace `apps/api` con NestJS sobre Fastify (`FastifyAdapter`, prefijo global `api`, puerto `process.env.PORT ?? 3000` en `0.0.0.0`) y Jest + ts-jest.
- Crear workspace `apps/web` con React + Vite (template `react-ts`), Tailwind CSS 4 vía `@tailwindcss/vite`, proxy de dev `/api` y `/ws` al backend, y Vitest + Testing Library.
- Crear workspace `packages/shared` (`@podsync/shared`) con enums (`RoomStatus`, `ParticipantRole`, `ParticipantStatus`) e interfaces base (`RoomSummary`, `ParticipantInfo`).
- Configurar ESLint + Prettier unificados a nivel raíz con reglas estrictas (`no-unused-vars` error, `no-explicit-any` warning) y `eslint-plugin-react-hooks` para web; opcionalmente `lint-staged` + `husky` en pre-commit.
- Añadir `.nvmrc` (Node LTS), `.editorconfig` (2 espacios, LF) y `.gitignore` Node.
- Establecer pipeline Turborepo: `build` (`dependsOn: ^build`, outputs `dist/**`), `dev` (cache:false, persistent:true), `lint`, `test`, `format`.

## Capabilities

### New Capabilities
- `monorepo-foundation`: Estructura de workspaces (apps/web, apps/api, packages/shared), gestor de paquetes pinneado vía Corepack, pipeline Turborepo y configuración TypeScript base compartida.
- `backend-bootstrap`: Aplicación NestJS sobre Fastify mínima viable (AppModule vacío, bootstrap con prefijo `api`, puerto configurable) lista para hospedar módulos de dominio.
- `frontend-bootstrap`: Aplicación React + Vite mínima con Tailwind CSS aplicado, proxy de desarrollo a backend (HTTP + WebSocket) y suite de testing con Vitest.
- `shared-types`: Paquete `@podsync/shared` con enums e interfaces compartidos entre frontend y backend, consumidos vía path alias y resolución de workspace.
- `code-quality-tooling`: ESLint + Prettier unificados, reglas TypeScript estrictas y scripts de formateo/linting agregados desde la raíz del monorepo.

### Modified Capabilities
<!-- Ninguna: no existen specs previas, este es el bootstrap del proyecto. -->

## Impact

- **Código nuevo**: archivos raíz (`package.json`, `pnpm-workspace.yaml`, `turbo.json`, `tsconfig.base.json`, `.nvmrc`, `.editorconfig`, `.gitignore`, configs ESLint/Prettier) y tres workspaces nuevos (`apps/api`, `apps/web`, `packages/shared`).
- **Dependencias añadidas**: Turborepo, pnpm (vía Corepack), NestJS + Fastify + reflect-metadata + rxjs, React + Vite + Tailwind 4, TypeScript, Jest + ts-jest, Vitest + Testing Library, ESLint + Prettier + plugins TS/React/import.
- **Toolchain**: requiere Corepack habilitado y Node LTS (versión fijada en `.nvmrc`).
- **Workflow**: trabajar en worktree `feature/TASK-001-monorepo-setup` desde `develop` (Gitflow), commits Conventional Commits, PR contra `develop` al completar.
- **Sin breaking changes**: punto de partida del proyecto; no hay consumidores previos.
- **Documentos de referencia**: `Docs/US/H1/US-001_Setup_Monorepo.md`, TDD §4.2 y §11.1.
