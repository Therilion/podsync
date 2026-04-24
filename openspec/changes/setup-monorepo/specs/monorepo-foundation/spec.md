## ADDED Requirements

### Requirement: Estructura de workspaces del monorepo
El repositorio SHALL contener un `pnpm-workspace.yaml` en la raíz que declare los globs `apps/*` y `packages/*`, y la estructura de directorios SHALL incluir como mínimo `apps/web`, `apps/api` y `packages/shared`.

#### Scenario: Resolución de workspaces por pnpm
- **WHEN** se ejecuta `pnpm -r list --depth -1` desde la raíz
- **THEN** la salida lista al menos los paquetes correspondientes a `apps/web`, `apps/api` y `packages/shared`

#### Scenario: Instalación unificada de dependencias
- **WHEN** se ejecuta `pnpm install` desde la raíz tras un clon limpio
- **THEN** finaliza sin errores y los `node_modules` quedan creados en la raíz y, donde proceda, en cada workspace

### Requirement: Gestor de paquetes pinneado vía Corepack
El `package.json` raíz SHALL declarar el campo `"packageManager"` con `pnpm@<versión-exacta>` para que Corepack fije la versión exacta usada por todos los entornos.

#### Scenario: Corepack respeta la versión declarada
- **WHEN** un desarrollador con Corepack habilitado ejecuta `pnpm --version` en la raíz
- **THEN** la versión devuelta coincide exactamente con la declarada en `packageManager`

### Requirement: Pipeline orquestado por Turborepo
El repositorio SHALL incluir un `turbo.json` que defina las tareas `build`, `dev`, `lint`, `test` y `format`. La tarea `build` MUST declarar `dependsOn: ["^build"]` y `outputs: ["dist/**"]`. La tarea `dev` MUST declarar `cache: false` y `persistent: true`.

#### Scenario: Build respeta orden topológico
- **WHEN** se ejecuta `pnpm build` desde la raíz
- **THEN** Turborepo construye `packages/shared` antes que `apps/api` y `apps/web` y termina sin errores

#### Scenario: Dev levanta procesos en paralelo
- **WHEN** se ejecuta `pnpm dev` desde la raíz
- **THEN** Turborepo arranca los procesos `dev` de `apps/api` y `apps/web` simultáneamente y mantiene ambos en ejecución hasta interrupción manual

### Requirement: Configuración TypeScript base compartida
La raíz SHALL contener `tsconfig.base.json` con `strict: true`, `module: "ESNext"`, `moduleResolution: "bundler"`, `target` alineado con la versión LTS de Node declarada en `.nvmrc`, y un path alias `@podsync/shared` que apunte a `packages/shared/src`.

#### Scenario: Workspaces extienden la configuración base
- **WHEN** se inspecciona el `tsconfig.json` de cualquier workspace
- **THEN** contiene `"extends": "../../tsconfig.base.json"`

#### Scenario: Strict mode aplica en compilación
- **WHEN** se introduce código con `any` implícito en cualquier workspace y se ejecuta `pnpm build`
- **THEN** la compilación falla por violación de strict mode

### Requirement: Archivos de entorno de desarrollo
El repositorio SHALL incluir `.nvmrc` con la versión LTS estable de Node, `.editorconfig` con indentación de 2 espacios y `end_of_line = lf`, y `.gitignore` con las exclusiones estándar para proyectos Node (incluyendo `node_modules`, `dist`, `.turbo`).

#### Scenario: Versión de Node fijada
- **WHEN** un desarrollador ejecuta `nvm use` en la raíz
- **THEN** se activa la versión declarada en `.nvmrc`

#### Scenario: Artefactos de build excluidos de git
- **WHEN** se ejecuta `pnpm build` y luego `git status`
- **THEN** los directorios `dist/` y `.turbo/` no aparecen como archivos sin seguimiento
