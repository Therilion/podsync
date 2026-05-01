## Context

US-001 ya estableció la base del monorepo (Turborepo + pnpm + apps NestJS y Vite). Para avanzar con el Hito 1 (auth, rooms, comunicación de voz) el backend necesita acceso local a:

- Una base de datos relacional (PostgreSQL) — fuente de verdad para usuarios, sesiones y rooms.
- Una caché/cola compatible con Redis — para rate limiting, sesiones efímeras y, más adelante, coordinación entre nodos del SFU.
- Un almacenamiento de objetos S3-compatible — para artefactos de grabaciones futuras y como sustrato del `StoragePort` (US-015).

El TDD del proyecto fija decisiones tecnológicas vinculantes (memoria de proyecto `project_storage_decision`):

- **Almacenamiento**: SeaweedFS en desarrollo, AWS S3 en producción. No sustituir por MinIO.
- **Caché**: Dragonfly en lugar de Redis. Mantiene compatibilidad de protocolo (`redis-cli`, drivers Redis estándar) pero con mejor footprint y menor latencia.

El entorno objetivo es la máquina de cualquier desarrollador con Docker Engine / Docker Desktop instalado. No se asume conectividad a servicios externos para el flujo de desarrollo local.

## Goals / Non-Goals

**Goals:**

- Un único comando (`docker compose up -d`) levanta los tres servicios lógicos en estado `healthy` en menos de 30 s.
- Configuración 100 % por variables de entorno con valores por defecto sensatos para desarrollo, materializados en `.env.example`.
- Datos persistentes entre `docker compose restart` mediante named volumes.
- Reseteo limpio mediante `docker compose down -v`.
- Bucket S3 inicial `podsync` creado de forma idempotente y disponible en cuanto el gateway esté listo.
- Topología SeaweedFS coherente: `master` → `volume` → `filer` → `s3`, con `depends_on` correctos.
- Documentación operativa mínima en el `README` del repo: cómo arrancar, cómo verificar, cómo limpiar.

**Non-Goals:**

- Configuración de producción (AWS S3, RDS, ElastiCache). Se aborda en cambios posteriores.
- Cliente NestJS para Postgres/Dragonfly/SeaweedFS (esto vive en US-003, US-008, US-015).
- Migraciones de Prisma o seeds (US-003, US-017).
- Observabilidad (logs/métricas) más allá de healthchecks básicos.
- TLS, autenticación robusta o secrets management — credenciales dev hardcodeadas con valores claramente marcados como `*_dev`.
- Soporte multi-arquitectura más allá de lo que las imágenes upstream ya proveen (linux/amd64, linux/arm64).

## Decisions

### 1. Dragonfly como reemplazo drop-in de Redis

**Decisión**: Usar `docker.dragonflydb.io/dragonflydb/dragonfly` con tag de versión major estable, exponiendo el puerto 6379.

**Rationale**: Decisión técnica del TDD. Dragonfly habla protocolo Redis y es compatible con `ioredis`/`node-redis`, por lo que el código de aplicación no se entera de la diferencia. La variable que consume el backend se llama `REDIS_URL` para no acoplar el código a la implementación concreta.

**Alternativas consideradas**: Redis OSS (descartada por decisión vinculante del TDD), KeyDB (no requerido).

### 2. SeaweedFS en topología master + volume + filer + s3

**Decisión**: Cuatro contenedores separados (`seaweedfs-master`, `seaweedfs-volume`, `seaweedfs-filer`, `seaweedfs-s3`) sobre la misma imagen `chrislusf/seaweedfs` con tag de versión estable. El gateway S3 escucha en el puerto 8333 y delega en el filer.

**Rationale**: Es la topología recomendada por upstream para exponer la API S3 con persistencia coherente. El filer es necesario para que el gateway S3 pueda mapear buckets a colecciones de volúmenes. Aunque introduce 4 contenedores en lugar de 1, mantiene la arquitectura cercana a producción y permite reutilizar la misma configuración con AWS S3 (cambiando `S3_ENDPOINT`).

**Alternativas consideradas**:
- *MinIO*: descartada por decisión vinculante del TDD.
- *SeaweedFS modo "all-in-one"*: más simple pero menos representativo de producción y con peor aislamiento de fallos.

### 3. Tag de versión major estable, nunca `latest`

**Decisión**: Para `postgres` se usa `postgres:<major>-alpine` (e.g. `17-alpine`). Para `dragonfly` y `seaweedfs` se fija un tag estable explícito (no `latest`). El major exacto se decide en implementación tomando la última major estable disponible al ejecutar la tarea, y se documenta en el `README`.

**Rationale**: `latest` rompe reproducibilidad: dos desarrolladores que hagan `pull` con días de diferencia pueden acabar con versiones distintas. La política del TDD (`Docs/US/H1/00_README.md` §"Política de Versiones") obliga a fijar major estable.

**Alternativas consideradas**: Pinning a digest SHA (más reproducible pero más fricción para upgrades menores; se reserva para producción).

### 4. Healthchecks y `depends_on: condition: service_healthy`

**Decisión**: Definir healthchecks para `postgres` (`pg_isready`) y `dragonfly` (`redis-cli ping`). Para SeaweedFS, encadenar dependencias con `depends_on` simple (master → volume/filer → s3) ya que upstream no provee un healthcheck estable de forma trivial; se usa el arranque secuencial. El backend de US-001, cuando se integre, esperará a que postgres y dragonfly estén `healthy`.

**Rationale**: Garantiza que el `compose up` termina en estado utilizable y permite a CI/dev scripts confiar en `--wait`. Para SeaweedFS, el riesgo de race se mitiga con `depends_on` y con un retry en el script de inicialización del bucket.

### 5. Bootstrap idempotente del bucket `podsync`

**Decisión**: Un servicio `seaweedfs-bucket-init` (one-shot, `restart: "no"`) ejecuta `docker/seaweedfs/init-bucket.sh`, que usa `aws-cli` (vía imagen `amazon/aws-cli`) o `s3cmd` apuntando al gateway con las credenciales de `s3.json`. El script comprueba si el bucket existe (`head-bucket`) y solo lo crea si falta.

**Rationale**: Cumple AC4 sin requerir intervención manual. La idempotencia evita errores en arranques sucesivos. Mantenerlo como servicio de Compose (en lugar de un `RUN` en una imagen custom) evita construir imágenes y respeta el principio de "todo declarativo en `docker-compose.yml`".

**Alternativas consideradas**: Construir una imagen custom de SeaweedFS con el bucket precreado (rechazada: complica upgrades de la imagen upstream).

### 6. `.env.example` único en la raíz, `.env` ignorado

**Decisión**: Un solo `.env.example` en la raíz del monorepo cubre Postgres, Dragonfly, SeaweedFS, Auth y App. `.gitignore` excluye `.env` (sin patrones más amplios que puedan tapar otros archivos).

**Rationale**: Simple y descubrible. Turborepo/pnpm workspaces leen variables del proceso, así que una sola fuente alimenta tanto `docker compose` como las apps. El TDD aún no requiere segmentación por entorno (`.env.development`, etc.) en este punto.

### 7. Named volumes, no bind mounts, para datos

**Decisión**: `postgres_data`, `dragonfly_data`, `seaweedfs_master_data`, `seaweedfs_volume_data`, `seaweedfs_filer_data` como named volumes. Bind mount solo para `docker/seaweedfs/s3.json` (configuración leída por SeaweedFS).

**Rationale**: Named volumes son portables entre macOS/Linux/Windows con Docker Desktop y evitan problemas de permisos UID/GID típicos de bind mounts en macOS. `docker compose down -v` los limpia atómicamente (AC8).

## Risks / Trade-offs

- **[Riesgo] Tiempo de arranque de SeaweedFS** → Cuatro contenedores secuenciados pueden acercarse o superar los 30 s en máquinas más lentas. *Mitigación*: el AC mide "todos los servicios necesarios para el backend" (postgres + dragonfly + s3 gateway alcanzable); documentar en `README` que la primera vez puede tardar por la descarga de imágenes.
- **[Riesgo] Race condition en el bootstrap del bucket** → El gateway S3 puede aceptar conexiones antes de que el filer esté plenamente listo. *Mitigación*: el script `init-bucket.sh` reintenta con backoff exponencial durante hasta ~30 s antes de fallar.
- **[Riesgo] Conflicto de puertos** (5432, 6379, 8333, 9333, 8888) con servicios ya instalados localmente → *Mitigación*: todos los puertos del host son configurables vía variables de entorno (`POSTGRES_PORT`, `DRAGONFLY_PORT`, `S3_PORT`); los puertos internos del cluster SeaweedFS no se exponen al host.
- **[Trade-off] Credenciales hardcodeadas en `s3.json`** → Aceptable solo para desarrollo. Documentar claramente en el `README` que `podsync_dev_key`/`podsync_dev_secret` no deben replicarse en producción.
- **[Trade-off] No se construye una imagen custom para inicialización** → A cambio se asume una pequeña imagen extra (`amazon/aws-cli`) en el grafo, ~100 MB. Aceptable.

## Migration Plan

No hay migración: este change añade infraestructura nueva. El plan de despliegue local es:

1. Desarrollador hace `pull` de la rama tras el merge.
2. Copia `.env.example` a `.env`.
3. Ejecuta `docker compose up -d` y espera a que `docker compose ps` muestre todos los servicios `healthy` (o `Exited (0)` para el bootstrap del bucket).
4. Verifica con los comandos del `README` (`pg_isready`, `redis-cli ping`, `curl` al gateway).

**Rollback**: `docker compose down -v` y revertir el commit. No hay datos compartidos en riesgo porque los volúmenes son locales por desarrollador.

## Open Questions

- ¿Qué major exacta de PostgreSQL se fija? Se decide al implementar tomando la última estable; debe documentarse en el `README` y en `.env.example` como comentario.
  - R. De acuerdo a la página de postgreesql, la última versión 
- ¿Se quiere también un comando `pnpm` (e.g. `pnpm dev:up`) que envuelva `docker compose up -d --wait`? Sugerido pero no obligatorio en este change; puede añadirse oportunísticamente en `package.json` raíz si encaja con la convención de US-001.
