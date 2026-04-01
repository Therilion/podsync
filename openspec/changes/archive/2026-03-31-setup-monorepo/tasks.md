## 1. Root Monorepo Setup

- [x] 1.1 Create root `package.json` with `"private": true`, `"name": "podsync"`, pnpm workspace scripts (`dev`, `build`, `lint`, `type-check`), and Turborepo as a devDependency
- [x] 1.2 Create `pnpm-workspace.yaml` defining `apps/*` and `packages/*` workspace globs
- [x] 1.3 Create `turbo.json` with pipeline definitions for `dev` (persistent, parallel), `build` (dependsOn: `^build`), `lint`, and `type-check`

## 2. Shared TypeScript Configuration (packages/tsconfig)

- [x] 2.1 Create `packages/tsconfig/package.json` with name `@podsync/tsconfig`
- [x] 2.2 Create `base.json` with shared compiler options (strict, ES2022 target, declaration, etc.)
- [x] 2.3 Create `react.json` extending base with JSX preserve, DOM lib, Vite-compatible settings
- [x] 2.4 Create `node.json` extending base with Node.js module resolution (CommonJS, Node types)

## 3. Shared Types Package (packages/shared-types)

- [x] 3.1 Create `packages/shared-types/package.json` with name `@podsync/shared-types`, devDependency on `@podsync/tsconfig`, and `build`/`type-check` scripts
- [x] 3.2 Create `tsconfig.json` extending `@podsync/tsconfig/base.json`
- [x] 3.3 Create empty barrel file `src/index.ts` with placeholder export

## 4. Frontend Workspace (apps/web)

- [x] 4.1 Scaffold React 19 + TypeScript + Vite app in `apps/web` using `pnpm create vite`
- [x] 4.2 Update `package.json` name to `@podsync/web`, add devDependency on `@podsync/tsconfig`
- [x] 4.3 Update `tsconfig.json` to extend `@podsync/tsconfig/react.json`
- [x] 4.4 Add `type-check` script (`tsc --noEmit`) and ensure `dev`, `build`, `lint` scripts exist

## 5. Backend Workspace (apps/api)

- [x] 5.1 Scaffold NestJS app in `apps/api` using `@nestjs/cli` with Fastify adapter
- [x] 5.2 Update `package.json` name to `@podsync/api`, add devDependency on `@podsync/tsconfig`
- [x] 5.3 Update `tsconfig.json` to extend `@podsync/tsconfig/node.json`
- [x] 5.4 Configure `main.ts` to use `FastifyAdapter` instead of Express
- [x] 5.5 Add `type-check` script and ensure `dev` uses `nest start --watch`

## 6. ESLint and Prettier Configuration

- [x] 6.1 Create root `eslint.config.mjs` with TypeScript and Prettier integration
- [x] 6.2 Create root `prettier.config.mjs` with project formatting rules
- [x] 6.3 Add React-specific ESLint rules for `apps/web`
- [x] 6.4 Ensure ESLint config works for NestJS decorators in `apps/api`

## 7. Verification

- [x] 7.1 Run `pnpm install` from root — all dependencies resolve without errors
- [x] 7.2 Run `pnpm lint` from root — zero errors across all workspaces
- [x] 7.3 Run `pnpm type-check` from root — zero errors across all workspaces
- [x] 7.4 Run `pnpm dev` from root — both dev servers start successfully via Turborepo
- [x] 7.5 Run `pnpm build` from root — all workspaces build without errors
