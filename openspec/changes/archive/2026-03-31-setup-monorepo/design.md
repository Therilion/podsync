## Context

PodSync is a greenfield project with no existing code beyond initial documentation. Before any application logic can be developed, the monorepo structure, build tooling, and code quality tooling must be established. This is the first step in Milestone H1 (Infrastructure & Basic Communication).

The project will have two main applications (React frontend, NestJS backend) plus shared packages, all managed under a single repository with Turborepo orchestration and pnpm workspaces.

## Goals / Non-Goals

**Goals:**
- Establish a pnpm workspace monorepo with Turborepo orchestration
- Create minimal app scaffolds for `apps/web` (React + Vite) and `apps/api` (NestJS + Fastify)
- Set up shared TypeScript configuration in `packages/tsconfig`
- Create an empty `packages/shared-types` package ready for future use
- Configure ESLint and Prettier at root level with workspace inheritance
- Enable `pnpm dev`, `pnpm build`, `pnpm lint`, and `pnpm type-check` from the root

**Non-Goals:**
- Docker or Docker Compose configuration (next atomic step)
- Environment variables or external service configuration
- Any business logic, API endpoints, UI components, or database setup
- CI/CD pipeline configuration
- Tailwind CSS or shadcn/ui setup (will come with first UI work)

## Decisions

### 1. pnpm as package manager

**Choice**: pnpm with workspaces over npm/yarn.
**Rationale**: pnpm provides strict dependency isolation via content-addressable storage, native workspace support, and faster installs. It pairs well with Turborepo and is the recommended package manager for Turborepo monorepos.
**Alternatives**: npm workspaces (slower, less strict), yarn berry (more complex, PnP can cause compatibility issues).

### 2. Turborepo for build orchestration

**Choice**: Turborepo over Nx or Lerna.
**Rationale**: Turborepo is lightweight, zero-config for basic setups, and integrates natively with pnpm workspaces. It provides task caching and parallel execution out of the box. Nx would be overkill for a project of this size; Lerna is deprecated in favor of Nx.

### 3. Shared tsconfig via workspace package

**Choice**: `packages/tsconfig` workspace with multiple base configs exported as files.
**Rationale**: Centralizes TypeScript configuration so all workspaces extend from the same base. Changes to compiler options propagate automatically. Each workspace extends the appropriate config (`base.json`, `react.json`, `node.json`).

### 4. ESLint flat config at root

**Choice**: ESLint 9 flat config (`eslint.config.mjs`) at root level, with workspace-specific overrides.
**Rationale**: Flat config is the current standard for ESLint 9+. A single root config reduces duplication; workspace configs extend it for framework-specific rules (React, NestJS).
**Alternative**: Per-workspace `.eslintrc` files (more duplication, legacy config format).

### 5. NestJS with Fastify adapter

**Choice**: Fastify adapter instead of default Express.
**Rationale**: Required by the technical specification (§4.2). Fastify provides better performance for the WebSocket-heavy workload PodSync will have.

### 6. Workspace naming convention

**Choice**: `@podsync/` scope for all packages (e.g., `@podsync/web`, `@podsync/api`, `@podsync/shared-types`, `@podsync/tsconfig`).
**Rationale**: Scoped names prevent conflicts with public npm packages and make internal dependencies explicit in import paths.

## Risks / Trade-offs

- **[React 19 ecosystem maturity]** → Some ESLint plugins may not fully support React 19 yet. Mitigation: use compatible versions and pin if needed.
- **[Turborepo cache invalidation]** → Misconfigured `turbo.json` inputs/outputs can cause stale builds. Mitigation: explicitly define inputs and outputs per task.
- **[Shared tsconfig coupling]** → A change to base tsconfig affects all workspaces. Mitigation: keep base config minimal; workspace configs add project-specific options.
