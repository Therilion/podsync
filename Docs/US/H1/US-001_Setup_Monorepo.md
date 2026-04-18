# US-001 — Setup del Monorepo y Entorno de Desarrollo

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** desarrollador,
> **quiero** tener un monorepo configurado con Turborepo, pnpm y Corepack,
> **para** poder trabajar con frontend y backend en un solo repositorio con builds optimizados y pipeline de tareas unificado.

**Referencia TDD:** §4.2 (Stack Seleccionado), §11.1
**Prioridad:** P0-Critical
**Estimación total:** L (1–2 días)
**Dependencias:** Ninguna (punto de partida)

### Criterios de Aceptación

1. El repositorio tiene estructura de monorepo con workspaces separados para `apps/web` (React + Vite), `apps/api` (NestJS + Fastify) y `packages/shared` (tipos compartidos).
2. `pnpm install` desde la raíz instala todas las dependencias de todos los workspaces.
3. `pnpm build` desde la raíz compila todos los workspaces en el orden correcto (shared → api/web).
4. `pnpm dev` levanta frontend y backend en paralelo con hot reload.
5. `pnpm lint` y `pnpm format` ejecutan ESLint y Prettier en todos los workspaces.
6. `pnpm test` ejecuta los tests de todos los workspaces.
7. Corepack está habilitado y fija la versión de pnpm en `package.json`.
8. TypeScript strict mode está habilitado en `tsconfig.base.json` con path aliases configurados.
9. El workspace `packages/shared` exporta al menos un tipo de ejemplo y se consume desde `apps/api` y `apps/web` sin errores de compilación.

### Tareas

#### TASK-001: Inicializar repositorio y configurar Turborepo

| Campo | Valor |
|-------|-------|
| **ID** | TASK-001 |
| **Tamaño** | M |
| **Prioridad** | P0-Critical |
| **Dependencias** | — |

**Especificación de implementación:**

1. Inicializar repositorio git con `.gitignore` para Node.js.
2. Crear `package.json` raíz con:
   - `"packageManager": "pnpm@<latest-stable>"` (Corepack lo fijará; usar la última versión estable al momento del setup).
   - Scripts: `dev`, `build`, `lint`, `format`, `test`.
3. Crear `pnpm-workspace.yaml`:
   ```yaml
   packages:
     - "apps/*"
     - "packages/*"
   ```
4. Crear `turbo.json` con pipeline:
   ```json
   {
     "$schema": "https://turbo.build/schema.json",
     "tasks": {
       "build": {
         "dependsOn": ["^build"],
         "outputs": ["dist/**"]
       },
       "dev": {
         "cache": false,
         "persistent": true
       },
       "lint": {},
       "test": {},
       "format": {}
     }
   }
   ```
5. Crear `tsconfig.base.json` en la raíz con:
   - `"strict": true`
   - `"target"` alineado con la versión LTS de Node.js en uso (e.g. `ES2023` o superior), `"module": "ESNext"`, `"moduleResolution": "bundler"`
   - Path aliases: `"@podsync/shared": ["packages/shared/src"]`
6. Crear `.nvmrc` con la última versión LTS estable de Node.js al momento del setup.
7. Crear `.editorconfig` con indentación de 2 espacios, LF como fin de línea.

**Verificación:** Ejecutar `corepack enable && pnpm install` sin errores. `turbo build` completa sin errores (workspaces vacíos).

---

#### TASK-002: Configurar workspace del backend (NestJS + Fastify)

| Campo | Valor |
|-------|-------|
| **ID** | TASK-002 |
| **Tamaño** | M |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-001 |

**Especificación de implementación:**

1. En `apps/api/`, inicializar proyecto NestJS con CLI o manualmente:
   ```bash
   pnpm add @nestjs/core @nestjs/common @nestjs/platform-fastify fastify reflect-metadata rxjs
   pnpm add -D @nestjs/cli @nestjs/testing typescript @types/node jest ts-jest @types/jest
   ```
2. Configurar `apps/api/tsconfig.json` que extiende `../../tsconfig.base.json`:
   - `"outDir": "./dist"`
   - `"rootDir": "./src"`
   - Decoradores habilitados: `"experimentalDecorators": true`, `"emitDecoratorMetadata": true`
3. Crear `apps/api/src/main.ts`:
   ```typescript
   import { NestFactory } from '@nestjs/core';
   import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
   import { AppModule } from './app.module';

   async function bootstrap() {
     const app = await NestFactory.create<NestFastifyApplication>(
       AppModule,
       new FastifyAdapter(),
     );
     app.setGlobalPrefix('api');
     await app.listen(process.env.PORT ?? 3000, '0.0.0.0');
   }
   bootstrap();
   ```
4. Crear `apps/api/src/app.module.ts` con un módulo raíz vacío.
5. Configurar Jest en `apps/api/jest.config.ts`:
   - Preset: `ts-jest`
   - Test regex: `.*\\.spec\\.ts$`
   - `moduleNameMapper` para path aliases de `@podsync/shared`.
6. Crear `apps/api/package.json` con scripts `dev`, `build`, `test`, `lint`, `start:prod`.
7. Configurar ESLint y Prettier exteniendo configs de la raíz.

**Tests TDD:**
- **Red:** Escribir test `app.module.spec.ts` que verifique que `AppModule` se instancia correctamente usando `Test.createTestingModule`.
- **Green:** Implementar `AppModule` mínimo.
- **Refactor:** N/A en este punto.

**Verificación:** `pnpm --filter api test` pasa. `pnpm --filter api build` genera dist sin errores.

---

#### TASK-003: Configurar workspace del frontend (React + Vite + TypeScript)

| Campo | Valor |
|-------|-------|
| **ID** | TASK-003 |
| **Tamaño** | M |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-001 |

**Especificación de implementación:**

1. En `apps/web/`, crear proyecto con Vite:
   ```bash
   pnpm create vite . --template react-ts
   ```
2. Instalar dependencias de UI:
   ```bash
   pnpm add tailwindcss @tailwindcss/vite
   ```
3. Configurar `apps/web/tsconfig.json` extendiendo `../../tsconfig.base.json` con ajustes para React (`"jsx": "react-jsx"`).
4. Configurar Tailwind CSS (última versión estable) en `vite.config.ts`:
   ```typescript
   import tailwindcss from '@tailwindcss/vite';
   export default defineConfig({
     plugins: [react(), tailwindcss()],
   });
   ```
5. Importar Tailwind en el CSS principal: `@import "tailwindcss";`.
6. Configurar proxy en `vite.config.ts` para redirigir `/api` y `/ws` al backend en desarrollo:
   ```typescript
   server: {
     proxy: {
       '/api': 'http://localhost:3000',
       '/ws': { target: 'ws://localhost:3000', ws: true },
     },
   }
   ```
7. Instalar y configurar Vitest para tests del frontend:
   ```bash
   pnpm add -D vitest @testing-library/react @testing-library/jest-dom jsdom
   ```
8. Crear `apps/web/package.json` con scripts `dev`, `build`, `test`, `preview`.

**Tests TDD:**
- **Red:** Escribir test que verifique que el componente `App` renderiza sin errores.
- **Green:** Implementar `App.tsx` mínimo con Tailwind aplicando un estilo básico.
- **Refactor:** N/A.

**Verificación:** `pnpm --filter web dev` levanta la app en el puerto configurado. `pnpm --filter web build` genera el bundle sin errores.

---

#### TASK-004: Crear workspace de tipos compartidos (packages/shared)

| Campo | Valor |
|-------|-------|
| **ID** | TASK-004 |
| **Tamaño** | S |
| **Prioridad** | P1-High |
| **Dependencias** | TASK-001 |

**Especificación de implementación:**

1. Crear `packages/shared/package.json` con `"name": "@podsync/shared"` y `"main": "./src/index.ts"`.
2. Crear `packages/shared/tsconfig.json` que extienda `../../tsconfig.base.json`.
3. Crear `packages/shared/src/index.ts` exportando tipos iniciales:
   ```typescript
   // Enums compartidos entre frontend y backend
   export enum RoomStatus {
     ACTIVE = 'active',
     CLOSED = 'closed',
   }

   export enum ParticipantRole {
     HOST = 'host',
     GUEST = 'guest',
   }

   export enum ParticipantStatus {
     CONNECTED = 'connected',
     DISCONNECTED = 'disconnected',
     LEFT = 'left',
   }

   // Tipos base
   export interface RoomSummary {
     id: string;
     code: string;
     status: RoomStatus;
     createdAt: string;
   }

   export interface ParticipantInfo {
     id: string;
     displayName: string;
     role: ParticipantRole;
     status: ParticipantStatus;
   }
   ```
4. Verificar que `apps/api` y `apps/web` pueden importar `@podsync/shared` sin errores de compilación.

**Tests TDD:**
- **Red:** Test en `apps/api` que importa `RoomStatus` de `@podsync/shared` y valida que `RoomStatus.ACTIVE === 'active'`.
- **Green:** Exportar los tipos.
- **Refactor:** N/A.

**Verificación:** `pnpm build` desde la raíz compila los tres workspaces sin errores. Los imports cross-workspace resuelven correctamente.

---

#### TASK-005: Configurar linting y formateo unificado

| Campo | Valor |
|-------|-------|
| **ID** | TASK-005 |
| **Tamaño** | S |
| **Prioridad** | P2-Medium |
| **Dependencias** | TASK-002, TASK-003, TASK-004 |

**Especificación de implementación:**

1. Crear configuración de ESLint en la raíz del monorepo con:
   - `@typescript-eslint/parser` y `@typescript-eslint/eslint-plugin`.
   - Reglas recomendadas de TypeScript + reglas estrictas (`no-unused-vars`, `no-explicit-any` como warning).
   - Plugin `eslint-plugin-react-hooks` para el workspace web.
   - Plugin `eslint-plugin-import` para orden de imports.
2. Crear `prettier.config.mjs` en la raíz:
   ```javascript
   export default {
     semi: true,
     singleQuote: true,
     trailingComma: 'all',
     printWidth: 100,
     tabWidth: 2,
   };
   ```
3. Crear script `lint` en turbo.json que ejecute ESLint en todos los workspaces.
4. Crear script `format` y `format:check` con Prettier.
5. Configurar lint-staged con husky para pre-commit (opcional, recomendado):
   ```json
   { "*.{ts,tsx}": ["eslint --fix", "prettier --write"] }
   ```

**Verificación:** `pnpm lint` ejecuta sin errores sobre el código existente. `pnpm format:check` pasa sin cambios pendientes.
