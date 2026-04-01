## Purpose

Establishes the monorepo structure, build orchestration, and tooling foundation for PodSync. Defines the workspace configuration, shared TypeScript setup, and development workflow that all project workspaces will follow.

## Requirements

### Requirement: pnpm workspace monorepo structure
The project SHALL use pnpm workspaces to manage a monorepo with the following workspace directories: `apps/*` and `packages/*`. The root `package.json` SHALL declare `"private": true` and define the workspace globs. A `pnpm-workspace.yaml` file SHALL define the workspace packages.

#### Scenario: Install all dependencies from root
- **WHEN** a developer runs `pnpm install` from the repository root
- **THEN** all workspace dependencies are installed correctly without errors

#### Scenario: Workspace packages are resolvable
- **WHEN** a workspace package declares a dependency on another workspace package (e.g., `@podsync/tsconfig`)
- **THEN** pnpm resolves it to the local workspace version via the `workspace:*` protocol

### Requirement: Turborepo build orchestration
The project SHALL use Turborepo as the monorepo build orchestrator. A `turbo.json` file at the root SHALL define pipelines for `dev`, `build`, `lint`, and `type-check` tasks. The `dev` task SHALL run in parallel with persistent mode. The `build` task SHALL respect dependency order. The `lint` and `type-check` tasks SHALL run in parallel across workspaces.

#### Scenario: Parallel dev servers
- **WHEN** a developer runs `pnpm dev` from the root
- **THEN** Turborepo starts both `apps/web` and `apps/api` dev servers in parallel

#### Scenario: Build respects dependency order
- **WHEN** a developer runs `pnpm build` from the root
- **THEN** Turborepo builds packages before apps, respecting the `dependsOn` configuration

#### Scenario: Lint across all workspaces
- **WHEN** a developer runs `pnpm lint` from the root
- **THEN** ESLint runs in all workspaces and reports zero errors on a clean setup

#### Scenario: Type-check across all workspaces
- **WHEN** a developer runs `pnpm type-check` from the root
- **THEN** TypeScript type checking runs in all workspaces and reports zero errors on a clean setup

### Requirement: Frontend workspace (apps/web)
The `apps/web` workspace SHALL be a React 19 application scaffolded with Vite and TypeScript. It SHALL be named `@podsync/web` in its `package.json`. It SHALL include `dev`, `build`, `lint`, and `type-check` scripts.

#### Scenario: Frontend dev server starts
- **WHEN** a developer runs `pnpm dev` from `apps/web` (or via Turborepo from root)
- **THEN** Vite starts a development server that serves the default React page without errors

#### Scenario: Frontend builds successfully
- **WHEN** a developer runs `pnpm build` from `apps/web`
- **THEN** Vite produces a production build in the `dist/` directory without errors

### Requirement: Backend workspace (apps/api)
The `apps/api` workspace SHALL be a NestJS application using the Fastify adapter. It SHALL be named `@podsync/api` in its `package.json`. It SHALL include `dev`, `build`, `lint`, and `type-check` scripts. The `dev` script SHALL use `nest start --watch`.

#### Scenario: Backend dev server starts
- **WHEN** a developer runs `pnpm dev` from `apps/api` (or via Turborepo from root)
- **THEN** NestJS starts with Fastify and the application bootstraps without errors

#### Scenario: Backend builds successfully
- **WHEN** a developer runs `pnpm build` from `apps/api`
- **THEN** NestJS compiles TypeScript to the `dist/` directory without errors

### Requirement: Shared types package (packages/shared-types)
The `packages/shared-types` workspace SHALL be named `@podsync/shared-types`. It SHALL export an empty barrel file (`index.ts`). It SHALL include a `build` and `type-check` script. It SHALL be ready for other workspaces to import types from.

#### Scenario: Shared types package builds
- **WHEN** a developer runs `pnpm build` from `packages/shared-types`
- **THEN** TypeScript compiles successfully producing type declarations

### Requirement: Shared TypeScript configuration (packages/tsconfig)
The `packages/tsconfig` workspace SHALL be named `@podsync/tsconfig`. It SHALL export base TypeScript configurations: `base.json` (shared compiler options), `react.json` (extends base with JSX and DOM lib settings), and `node.json` (extends base with Node.js module resolution). Workspaces SHALL extend these configs in their own `tsconfig.json`.

#### Scenario: Workspaces extend shared tsconfig
- **WHEN** `apps/web/tsconfig.json` extends `@podsync/tsconfig/react.json`
- **THEN** TypeScript resolves the configuration and compiles without errors

#### Scenario: Node config used by backend
- **WHEN** `apps/api/tsconfig.json` extends `@podsync/tsconfig/node.json`
- **THEN** TypeScript resolves the configuration with Node.js-appropriate settings

### Requirement: ESLint and Prettier configuration
The project SHALL have ESLint 9 configured with a flat config file (`eslint.config.mjs`) at the root. Prettier SHALL be configured at the root (`prettier.config.mjs`). ESLint SHALL integrate with Prettier via `eslint-config-prettier`. Each workspace MAY extend the root config with framework-specific rules.

#### Scenario: ESLint passes on clean codebase
- **WHEN** a developer runs `pnpm lint` from the root on the initial setup
- **THEN** ESLint reports zero errors and zero warnings

#### Scenario: Prettier formatting is consistent
- **WHEN** a developer checks formatting with Prettier
- **THEN** all source files conform to the Prettier configuration
