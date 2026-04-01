## Why

PodSync needs a monorepo foundation before any application code can be developed. A well-structured Turborepo workspace with shared tooling (TypeScript, ESLint, Prettier) ensures consistent developer experience across frontend and backend from day one, and prevents configuration drift as the project grows.

## What Changes

- Initialize pnpm workspace monorepo with Turborepo as the build orchestrator
- Create `apps/web` workspace: React 19 + TypeScript + Vite (default scaffold, no UI logic)
- Create `apps/api` workspace: NestJS + Fastify adapter (empty AppModule, no endpoints)
- Create `packages/shared-types` workspace: empty TypeScript package for future shared types
- Create `packages/tsconfig` workspace: shared base tsconfig configurations
- Configure ESLint + Prettier at root level with inheritance in each workspace
- Add root-level scripts (`dev`, `build`, `lint`, `type-check`) orchestrated by Turborepo

## Capabilities

### New Capabilities

- `monorepo-tooling`: Turborepo workspace structure, shared TypeScript configuration, ESLint + Prettier setup, and pnpm workspace orchestration

### Modified Capabilities

_None — this is the initial project setup._

## Impact

- **Dependencies**: Introduces pnpm as package manager, Turborepo, React 19, Vite, NestJS, Fastify, TypeScript, ESLint, and Prettier as project dependencies
- **Project structure**: Establishes the `apps/` and `packages/` directory convention that all future code will follow
- **Developer workflow**: All subsequent changes will use `pnpm dev`, `pnpm build`, `pnpm lint`, and `pnpm type-check` from the root
- **No Docker, no env vars, no business logic** — those are separate follow-up changes
