# Capability: Shared Types

## Purpose

Defines the `packages/shared` workspace published as `@podsync/shared`. Establishes the shared enums and base interfaces consumed by both the backend and frontend, and the path alias resolution that makes cross-workspace imports work across all toolchains.

---

## Requirements

### Requirement: Workspace `packages/shared` publicado como `@podsync/shared`
El workspace `packages/shared` SHALL declarar en su `package.json` el nombre `@podsync/shared` y `main: "./src/index.ts"`. Su `tsconfig.json` MUST extender `../../tsconfig.base.json`.

#### Scenario: Resolución del paquete por nombre
- **WHEN** un workspace consumidor declara `"@podsync/shared": "workspace:*"` en sus dependencias y se ejecuta `pnpm install`
- **THEN** la dependencia es enlazada al workspace local sin descargar desde un registro remoto

### Requirement: Enums compartidos exportados desde el barrel
El `packages/shared/src/index.ts` SHALL exportar los siguientes enums con sus valores literales:
- `RoomStatus` con miembros `ACTIVE = 'active'`, `CLOSED = 'closed'`.
- `ParticipantRole` con miembros `HOST = 'host'`, `GUEST = 'guest'`.
- `ParticipantStatus` con miembros `CONNECTED = 'connected'`, `DISCONNECTED = 'disconnected'`, `LEFT = 'left'`.

#### Scenario: Enums consumidos desde el backend
- **WHEN** un test en `apps/api` ejecuta `import { RoomStatus } from '@podsync/shared';` y evalúa `RoomStatus.ACTIVE === 'active'`
- **THEN** la aserción es verdadera

#### Scenario: Enums consumidos desde el frontend
- **WHEN** un módulo en `apps/web` importa `ParticipantRole` desde `@podsync/shared`
- **THEN** TypeScript reconoce los miembros `HOST` y `GUEST` y la compilación tiene éxito

### Requirement: Interfaces base exportadas desde el barrel
El `packages/shared/src/index.ts` SHALL exportar las interfaces:
- `RoomSummary` con campos `id: string`, `code: string`, `status: RoomStatus`, `createdAt: string`.
- `ParticipantInfo` con campos `id: string`, `displayName: string`, `role: ParticipantRole`, `status: ParticipantStatus`.

#### Scenario: Tipado disponible en consumidores
- **WHEN** un consumidor declara una variable `const r: RoomSummary = { ... };` con todos los campos requeridos
- **THEN** TypeScript valida la asignación sin errores

#### Scenario: Campo faltante detectado en compilación
- **WHEN** un consumidor declara una variable `const r: RoomSummary = { id: 'x' };` (faltan campos)
- **THEN** TypeScript reporta error de compilación

### Requirement: Resolución del path alias en todos los toolchains
El alias `@podsync/shared` SHALL resolver a `packages/shared/src` en TypeScript (vía `tsconfig.base.json`), en Jest (vía `moduleNameMapper`) y en Vite (vía resolución de workspace estándar de pnpm).

#### Scenario: Compilación cross-workspace exitosa
- **WHEN** se ejecuta `pnpm build` desde la raíz
- **THEN** los tres workspaces compilan sin errores de resolución de módulo
