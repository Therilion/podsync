## 1. Preparación de rama y entorno

- [x] 1.1 Crear worktree `feature/TASK-001-monorepo-setup` desde `develop` (`git worktree add ../podsync-feature-task-001 feature/TASK-001-monorepo-setup`)
- [x] 1.2 Habilitar Corepack en la máquina de desarrollo (`corepack enable`)
- [x] 1.3 Verificar versión LTS de Node activa con `node --version` antes de continuar

## 2. TASK-001 — Inicializar repositorio y Turborepo

- [x] 2.1 Crear `.gitignore` con exclusiones Node (`node_modules`, `dist`, `.turbo`, `*.log`, `.env*`, coverage)
- [x] 2.2 Crear `package.json` raíz con `"private": true`, `"packageManager": "pnpm@<latest-stable>"` y scripts `dev`, `build`, `lint`, `format`, `format:check`, `test`
- [x] 2.3 Crear `pnpm-workspace.yaml` con `packages: ["apps/*", "packages/*"]`
- [x] 2.4 Crear `turbo.json` con tareas `build` (dependsOn `^build`, outputs `dist/**`), `dev` (cache:false, persistent:true), `lint`, `test`, `format`
- [x] 2.5 Crear `tsconfig.base.json` con `strict: true`, `module: "ESNext"`, `moduleResolution: "bundler"`, target alineado a Node LTS y path alias `@podsync/shared` → `packages/shared/src`
- [x] 2.6 Crear `.nvmrc` con la versión LTS de Node
- [x] 2.7 Crear `.editorconfig` (2 espacios, LF, charset utf-8, insert_final_newline)
- [x] 2.8 Instalar Turborepo como devDependency en la raíz (`pnpm add -Dw turbo`)
- [x] 2.9 Verificar: `corepack enable && pnpm install` finaliza sin errores y `pnpm turbo --version` responde
- [x] 2.10 Commit: `feat(monorepo): bootstrap turborepo + pnpm workspaces`

## 3. TASK-004 — Workspace `packages/shared` (precede a api/web por consumo de tipos)

- [ ] 3.1 Crear estructura `packages/shared/{src,}` con `package.json` (`name: "@podsync/shared"`, `main: "./src/index.ts"`, `types: "./src/index.ts"`, `version: "0.0.0"`, `private: true`)
- [ ] 3.2 Crear `packages/shared/tsconfig.json` extendiendo `../../tsconfig.base.json` con `outDir: "./dist"` y `rootDir: "./src"`
- [ ] 3.3 Crear `packages/shared/src/index.ts` exportando enums `RoomStatus`, `ParticipantRole`, `ParticipantStatus` e interfaces `RoomSummary`, `ParticipantInfo` según spec
- [ ] 3.4 Verificar: `pnpm --filter @podsync/shared build` compila sin errores
- [ ] 3.5 Commit: `feat(shared): add @podsync/shared with base enums and interfaces`

## 4. TASK-002 — Backend NestJS + Fastify (TDD)

- [ ] 4.1 Crear `apps/api/package.json` con `name: "api"`, dependencia `"@podsync/shared": "workspace:*"`, scripts `dev`, `build`, `test`, `lint`, `start:prod`
- [ ] 4.2 Instalar deps runtime: `pnpm --filter api add @nestjs/core @nestjs/common @nestjs/platform-fastify fastify reflect-metadata rxjs`
- [ ] 4.3 Instalar devDeps: `pnpm --filter api add -D @nestjs/cli @nestjs/testing typescript @types/node jest ts-jest @types/jest`
- [ ] 4.4 Crear `apps/api/tsconfig.json` extendiendo base, con `outDir: "./dist"`, `rootDir: "./src"`, `experimentalDecorators: true`, `emitDecoratorMetadata: true`
- [ ] 4.5 Crear `apps/api/jest.config.ts` con preset `ts-jest`, `testRegex: ".*\\.spec\\.ts$"`, `moduleNameMapper` para `@podsync/shared` → `<rootDir>/../../packages/shared/src`
- [ ] 4.6 **RED**: Crear `apps/api/src/app.module.spec.ts` que verifica que `AppModule` se instancia con `Test.createTestingModule({ imports: [AppModule] }).compile()`; ejecutar `pnpm --filter api test` y confirmar fallo
- [ ] 4.7 **GREEN**: Crear `apps/api/src/app.module.ts` con `@Module({})` vacío; rerun tests y confirmar verde
- [ ] 4.8 Crear `apps/api/src/main.ts` con `NestFactory.create<NestFastifyApplication>(AppModule, new FastifyAdapter())`, `setGlobalPrefix('api')` y `listen(process.env.PORT ?? 3000, '0.0.0.0')`
- [ ] 4.9 Crear test que importe `RoomStatus` de `@podsync/shared` y valide `RoomStatus.ACTIVE === 'active'` (cubre TDD de TASK-004 desde api)
- [ ] 4.10 Verificar: `pnpm --filter api test` pasa, `pnpm --filter api build` genera `dist/` sin errores, `pnpm --filter api dev` arranca en puerto 3000
- [ ] 4.11 Commit: `feat(api): bootstrap nestjs + fastify with empty AppModule`

## 5. TASK-003 — Frontend React + Vite (TDD)

- [ ] 5.1 Inicializar `apps/web` con `pnpm create vite apps/web --template react-ts` (o equivalente manual con la misma estructura)
- [ ] 5.2 Ajustar `apps/web/package.json`: `name: "web"`, añadir dependencia `"@podsync/shared": "workspace:*"`, scripts `dev`, `build`, `test`, `preview`, `lint`
- [ ] 5.3 Instalar Tailwind 4: `pnpm --filter web add tailwindcss @tailwindcss/vite`
- [ ] 5.4 Instalar testing: `pnpm --filter web add -D vitest @testing-library/react @testing-library/jest-dom jsdom @types/jsdom`
- [ ] 5.5 Ajustar `apps/web/tsconfig.json` para extender `../../tsconfig.base.json` con `jsx: "react-jsx"` y los includes/lib que requiera React+DOM
- [ ] 5.6 Configurar `apps/web/vite.config.ts` con plugins `react()` y `tailwindcss()`, y `server.proxy` para `/api` → `http://localhost:3000` y `/ws` → `{ target: 'ws://localhost:3000', ws: true }`
- [ ] 5.7 Configurar bloque `test` de Vitest en `vite.config.ts` (o `vitest.config.ts`) con `environment: 'jsdom'`, `globals: true`, `setupFiles` que importen `@testing-library/jest-dom`
- [ ] 5.8 Reemplazar/crear CSS principal con `@import "tailwindcss";`
- [ ] 5.9 **RED**: Crear `apps/web/src/App.test.tsx` que renderiza `<App />` y assertea por contenido visible; ejecutar `pnpm --filter web test` y confirmar fallo
- [ ] 5.10 **GREEN**: Implementar `apps/web/src/App.tsx` mínimo con un elemento que muestre el contenido esperado y aplique al menos una clase Tailwind (e.g. `text-2xl font-bold`); rerun tests y confirmar verde
- [ ] 5.11 Verificar: `pnpm --filter web dev` levanta el servidor con HMR; `pnpm --filter web build` genera bundle sin errores
- [ ] 5.12 Commit: `feat(web): bootstrap react + vite + tailwind with App smoke test`

## 6. TASK-005 — Linting y formateo unificado

- [ ] 6.1 Instalar en raíz: `pnpm add -Dw eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin eslint-plugin-import prettier`
- [ ] 6.2 Instalar plugin React específico para web: `pnpm --filter web add -D eslint-plugin-react-hooks eslint-plugin-react`
- [ ] 6.3 Crear `eslint.config.mjs` (flat config) en raíz con: parser TS, plugins import + typescript, reglas `no-unused-vars` error y `no-explicit-any` warning, override para `apps/web` con `react-hooks/rules-of-hooks` y `react-hooks/exhaustive-deps`
- [ ] 6.4 Crear `prettier.config.mjs` en raíz con `semi:true, singleQuote:true, trailingComma:'all', printWidth:100, tabWidth:2`
- [ ] 6.5 Añadir `.prettierignore` con `dist`, `node_modules`, `.turbo`, `coverage`
- [ ] 6.6 Añadir scripts en cada workspace: `lint: "eslint . --max-warnings=0"` (o ajustar según necesidad)
- [ ] 6.7 Verificar: `pnpm lint` desde la raíz pasa sin errores; `pnpm format:check` pasa sin diffs
- [ ] 6.8 (Opcional) Configurar husky + lint-staged: `pnpm add -Dw husky lint-staged`, `pnpm exec husky init`, hook `pre-commit` con `pnpm lint-staged`, config `"*.{ts,tsx}": ["eslint --fix", "prettier --write"]`
- [ ] 6.9 Commit: `chore(tooling): unify eslint + prettier across workspaces`

## 7. Verificación end-to-end

- [ ] 7.1 Ejecutar `pnpm install` desde la raíz en clone limpio (o tras `rm -rf node_modules`) y confirmar éxito
- [ ] 7.2 Ejecutar `pnpm build` desde la raíz y confirmar orden topológico (`shared` → `api`/`web`) sin errores
- [ ] 7.3 Ejecutar `pnpm dev` y verificar que ambos servidores levantan en paralelo con HMR
- [ ] 7.4 Probar en navegador que `apps/web` muestra el contenido inicial con Tailwind aplicado y que `fetch('/api')` se proxya al backend
- [ ] 7.5 Ejecutar `pnpm test` y confirmar que las suites de api y web pasan
- [ ] 7.6 Ejecutar `pnpm lint` y `pnpm format:check` sin errores
- [ ] 7.7 Confirmar que `corepack enable && pnpm --version` devuelve la versión declarada en `packageManager`

## 8. Cierre y entrega

- [ ] 8.1 Revisar diff completo del worktree y limpiar artefactos accidentales
- [ ] 8.2 Push de la rama `feature/TASK-001-monorepo-setup` al remoto
- [ ] 8.3 Abrir PR contra `develop` con descripción que referencie US-001 y enlace al change OpenSpec `setup-monorepo`
- [ ] 8.4 Tras merge a `develop`, eliminar el worktree (`git worktree remove ../podsync-feature-task-001`)
- [ ] 8.5 Ejecutar `/opsx:archive setup-monorepo` para archivar el change y sincronizar specs
