## ADDED Requirements

### Requirement: Workspace `apps/api` con NestJS sobre Fastify
El workspace `apps/api` SHALL inicializarse con NestJS usando `@nestjs/platform-fastify` como adaptador HTTP. Las dependencias mínimas MUST incluir `@nestjs/core`, `@nestjs/common`, `@nestjs/platform-fastify`, `fastify`, `reflect-metadata` y `rxjs`.

#### Scenario: Adaptador Fastify activo en bootstrap
- **WHEN** se inspecciona `apps/api/src/main.ts`
- **THEN** la aplicación se crea con `NestFactory.create<NestFastifyApplication>(AppModule, new FastifyAdapter())`

### Requirement: Bootstrap con prefijo global y puerto configurable
El bootstrap del backend SHALL fijar un prefijo global de rutas `api`, escuchar en `0.0.0.0` y en el puerto resuelto por `process.env.PORT ?? 3000`.

#### Scenario: Servidor responde bajo prefijo `api`
- **WHEN** se ejecuta `pnpm --filter api dev` y se realiza una petición HTTP a `http://localhost:3000/api/<ruta-existente>`
- **THEN** la petición es enrutada por NestJS sin requerir prefijo adicional

#### Scenario: Puerto configurable por variable de entorno
- **WHEN** se ejecuta `PORT=4000 pnpm --filter api dev`
- **THEN** el servidor escucha en el puerto `4000`

### Requirement: Módulo raíz mínimo
El backend SHALL exponer un `AppModule` raíz vacío en `apps/api/src/app.module.ts` que sirva como punto de extensión para módulos de dominio futuros.

#### Scenario: AppModule se instancia correctamente
- **WHEN** se ejecuta el test que invoca `Test.createTestingModule({ imports: [AppModule] }).compile()`
- **THEN** la promesa resuelve sin errores y devuelve una instancia de testing module

### Requirement: Configuración TypeScript con decoradores
El `apps/api/tsconfig.json` SHALL extender `../../tsconfig.base.json` y habilitar `experimentalDecorators: true` y `emitDecoratorMetadata: true`. MUST declarar `outDir: "./dist"` y `rootDir: "./src"`.

#### Scenario: Decoradores compilan sin error
- **WHEN** se ejecuta `pnpm --filter api build` con código que usa `@Module`, `@Injectable` u otros decoradores de NestJS
- **THEN** la compilación produce `dist/` sin errores

### Requirement: Configuración Jest con ts-jest y resolución de tipos compartidos
El workspace SHALL incluir `apps/api/jest.config.ts` con preset `ts-jest`, `testRegex: ".*\\.spec\\.ts$"` y `moduleNameMapper` que resuelva `@podsync/shared` a `packages/shared/src`.

#### Scenario: Jest descubre y ejecuta tests
- **WHEN** se ejecuta `pnpm --filter api test`
- **THEN** Jest detecta los archivos `*.spec.ts` y ejecuta sus suites sin errores de resolución de módulo

#### Scenario: Tests pueden importar desde @podsync/shared
- **WHEN** un `*.spec.ts` importa un símbolo desde `@podsync/shared`
- **THEN** Jest resuelve el módulo y el test se ejecuta sin error de "Cannot find module"

### Requirement: Scripts de workspace
El `apps/api/package.json` SHALL exponer los scripts `dev`, `build`, `test`, `lint` y `start:prod`.

#### Scenario: Scripts disponibles vía pnpm
- **WHEN** se ejecuta `pnpm --filter api run` sin argumento
- **THEN** la salida lista los scripts `dev`, `build`, `test`, `lint` y `start:prod`
