## Why

El monorepo (US-001) ya está en marcha pero el backend NestJS no tiene aún ningún servicio de datos al que conectarse: PostgreSQL, una caché compatible con Redis y un almacenamiento de objetos S3-compatible. Sin estas piezas no es posible avanzar a US-003 (Prisma), US-015 (StoragePort) ni a la cadena de auth y rooms del Hito 1, y cada desarrollador acabaría montando sus propias dependencias locales con divergencias inevitables.

US-002 (TASK-006) resuelve esto introduciendo una infraestructura de desarrollo reproducible mediante Docker Compose que cualquier desarrollador pueda levantar con un solo comando, sin dependencias externas, y con datos persistentes entre reinicios.

## What Changes

- Añadir un `docker-compose.yml` en la raíz del monorepo que orquesta tres servicios lógicos:
  - **PostgreSQL** (imagen `-alpine`, major estable) en `localhost:${POSTGRES_PORT:-5432}` con healthcheck (`pg_isready`).
  - **Dragonfly** (sustituto drop-in de Redis, decisión vinculante) en `localhost:${DRAGONFLY_PORT:-6379}` con healthcheck (`redis-cli ping`).
  - **SeaweedFS** en topología master + volume + filer + s3 gateway, exponiendo la API S3 en `localhost:${S3_PORT:-8333}`.
- Crear `docker/seaweedfs/s3.json` con las identidades S3 de desarrollo y `docker/seaweedfs/init-bucket.sh` para crear el bucket inicial `podsync` de forma idempotente al arrancar.
- Crear `.env.example` en la raíz con todas las variables documentadas (PostgreSQL, Dragonfly, SeaweedFS, JWT/Auth, App) y actualizar `.gitignore` para excluir `.env` reales.
- Definir named volumes para persistir datos entre reinicios y permitir reseteo total con `docker compose down -v`.
- Documentar en el `README` del repositorio cómo levantar el entorno y cómo verificar cada servicio.
- Política de versiones: usar siempre tag de major estable (p. ej. `postgres:17-alpine`), nunca `latest` para imágenes de Postgres; documentar el major elegido.

No hay cambios *breaking* respecto al estado actual: el monorepo todavía no consume estos servicios.

## Capabilities

### New Capabilities

- `dev-infrastructure`: Orquestación local con Docker Compose de los servicios de datos (PostgreSQL, Dragonfly, SeaweedFS) que el backend necesita en desarrollo, incluyendo configuración por variables de entorno, healthchecks, persistencia mediante named volumes y bootstrap del bucket S3 inicial.

### Modified Capabilities

<!-- Ninguna. Las capabilities existentes (monorepo-foundation, backend-bootstrap, frontend-bootstrap, code-quality-tooling, shared-types) no cambian sus requirements; solo se les añade una dependencia operacional opcional sobre `dev-infrastructure` documentada en el README. -->

## Impact

- **Nuevos archivos**: `docker-compose.yml`, `docker/seaweedfs/s3.json`, `docker/seaweedfs/init-bucket.sh`, `.env.example`.
- **Modificados**: `.gitignore` (excluir `.env`), `README.md` (instrucciones de arranque y verificación).
- **Backend NestJS** (`apps/api` o equivalente de US-001): consumirá `DATABASE_URL`, `REDIS_URL` y las variables `S3_*` en runtime. No se introduce código de cliente en este change; solo se garantiza que las variables existan y los servicios estén accesibles.
- **Dependencias externas**: requiere Docker Engine / Docker Desktop en la máquina del desarrollador. No introduce nuevas dependencias npm/pnpm.
- **Bloquea/desbloquea**: una vez completado, desbloquea US-003 (esquema BD con Prisma), US-015 (StoragePort) y toda la cadena de auth/rooms del Hito 1.
- **Producción**: fuera de alcance. La configuración de S3 real (AWS) y Postgres gestionado se aborda en cambios posteriores (US-015 / fase prod).
