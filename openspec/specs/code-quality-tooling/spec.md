# Capability: Code Quality Tooling

## Purpose

Centralizes ESLint and Prettier configuration at the monorepo root so all workspaces share the same linting rules and formatting standards. Exposes aggregate scripts from the root `package.json` and optionally wires a pre-commit hook via Husky + lint-staged.

---

## Requirements

### Requirement: ESLint configurado a nivel raíz para todos los workspaces
La raíz del monorepo SHALL incluir una configuración ESLint que use `@typescript-eslint/parser` y `@typescript-eslint/eslint-plugin`, integre `eslint-plugin-react-hooks` para el workspace `apps/web` y `eslint-plugin-import` para orden de imports en todos los workspaces.

#### Scenario: Lint cubre los tres workspaces
- **WHEN** se ejecuta `pnpm lint` desde la raíz
- **THEN** ESLint analiza los archivos TypeScript de `apps/api`, `apps/web` y `packages/shared` y reporta resultados unificados

#### Scenario: Reglas TypeScript estrictas activas
- **WHEN** un archivo introduce una variable no usada
- **THEN** ESLint reporta un error por la regla `no-unused-vars`

#### Scenario: `any` explícito reportado como warning
- **WHEN** un archivo declara un tipo `any` explícito
- **THEN** ESLint reporta una advertencia (no error) por la regla `no-explicit-any`

### Requirement: Prettier configurado a nivel raíz
La raíz SHALL incluir `prettier.config.mjs` con `semi: true`, `singleQuote: true`, `trailingComma: 'all'`, `printWidth: 100` y `tabWidth: 2`.

#### Scenario: Verificación de formato
- **WHEN** se ejecuta `pnpm format:check` sobre el código existente
- **THEN** Prettier termina con código de salida 0 sin reportar diffs

#### Scenario: Aplicación de formato
- **WHEN** se ejecuta `pnpm format` sobre archivos no formateados
- **THEN** Prettier reescribe los archivos para cumplir la configuración

### Requirement: Scripts de calidad agregados desde la raíz
El `package.json` raíz SHALL exponer los scripts `lint`, `format` y `format:check`, ejecutables desde la raíz vía `pnpm` y orquestados por Turborepo cuando aplique.

#### Scenario: Scripts disponibles
- **WHEN** se ejecuta `pnpm run` sin argumento desde la raíz
- **THEN** la salida lista los scripts `dev`, `build`, `lint`, `format`, `format:check` y `test`

### Requirement: Hook pre-commit opcional con lint-staged y husky
El repositorio MAY incluir `husky` con un hook `pre-commit` que dispare `lint-staged` con la regla `"*.{ts,tsx}": ["eslint --fix", "prettier --write"]`. La inclusión es opcional; si se omite, no SHALL bloquear el cierre del change.

#### Scenario: Pre-commit limpia archivos staged (si está habilitado)
- **WHEN** husky+lint-staged están instalados y se ejecuta `git commit` sobre archivos `.ts/.tsx` con problemas de formato corregibles
- **THEN** lint-staged ejecuta `eslint --fix` y `prettier --write` y el commit procede con los archivos ya corregidos
