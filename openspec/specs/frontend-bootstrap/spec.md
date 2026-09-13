# Capability: Frontend Bootstrap

## Purpose

Defines the initial structure of the `apps/web` workspace: React + Vite application, Tailwind CSS integration via the official Vite plugin, dev proxy to the backend, TypeScript configuration for JSX, Vitest test setup, and workspace scripts.

---

## Requirements

### Requirement: Workspace `apps/web` con React + Vite
El workspace `apps/web` SHALL inicializarse con Vite usando el template `react-ts`. Las dependencias mínimas MUST incluir `react`, `react-dom` y, en devDependencies, `vite` y `@vitejs/plugin-react` (o equivalente del template oficial).

#### Scenario: Dev server arranca con HMR
- **WHEN** se ejecuta `pnpm --filter web dev`
- **THEN** Vite arranca en el puerto configurado y la aplicación es accesible vía navegador con Hot Module Replacement activo

#### Scenario: Build produce bundle de producción
- **WHEN** se ejecuta `pnpm --filter web build`
- **THEN** Vite genera los artefactos en `dist/` sin errores

### Requirement: Tailwind CSS integrado vía plugin oficial Vite
El frontend SHALL configurar Tailwind CSS mediante el plugin `@tailwindcss/vite` registrado en `apps/web/vite.config.ts`, y el CSS principal SHALL importar Tailwind con `@import "tailwindcss";`.

#### Scenario: Clases utilitarias se aplican en runtime
- **WHEN** un componente renderiza un elemento con clases Tailwind (e.g. `class="text-lg font-bold"`)
- **THEN** el elemento muestra los estilos correspondientes en el navegador

### Requirement: Proxy de desarrollo a backend
El `vite.config.ts` SHALL configurar `server.proxy` para redirigir `/api` a `http://localhost:3000` y `/ws` a `ws://localhost:3000` con `ws: true`.

#### Scenario: Petición HTTP relativa llega al backend
- **WHEN** el frontend en dev hace `fetch('/api/health')` y el backend está corriendo en `localhost:3000`
- **THEN** la petición es proxeada y la respuesta proviene del backend sin error de CORS

#### Scenario: Conexión WebSocket relativa llega al backend
- **WHEN** el frontend en dev abre una conexión WebSocket a `/ws/<ruta>`
- **THEN** la conexión es proxeada al backend en `ws://localhost:3000/ws/<ruta>`

### Requirement: Configuración TypeScript para React
El `apps/web/tsconfig.json` SHALL extender `../../tsconfig.base.json` y declarar `jsx: "react-jsx"`.

#### Scenario: JSX compila sin importación explícita de React
- **WHEN** un componente `.tsx` usa JSX sin importar `React` explícitamente
- **THEN** Vite y `tsc` lo compilan sin errores

### Requirement: Suite de testing con Vitest
El workspace SHALL incluir Vitest configurado con entorno `jsdom`, junto con `@testing-library/react` y `@testing-library/jest-dom` como devDependencies.

#### Scenario: Test unitario de componente pasa
- **WHEN** se ejecuta `pnpm --filter web test` con un test que renderiza `App` usando `@testing-library/react`
- **THEN** Vitest ejecuta el test y reporta éxito sin errores de configuración

#### Scenario: Matchers de jest-dom disponibles
- **WHEN** un test usa matchers como `toBeInTheDocument()`
- **THEN** los matchers están registrados y el test los evalúa correctamente

### Requirement: Scripts de workspace
El `apps/web/package.json` SHALL exponer los scripts `dev`, `build`, `test` y `preview`.

#### Scenario: Scripts disponibles vía pnpm
- **WHEN** se ejecuta `pnpm --filter web run` sin argumento
- **THEN** la salida lista los scripts `dev`, `build`, `test` y `preview`
