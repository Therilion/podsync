# US-002 — Infraestructura con Docker Compose

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** desarrollador,
> **quiero** tener todos los servicios de infraestructura (PostgreSQL, Dragonfly, SeaweedFS) configurados en Docker Compose,
> **para** poder levantar el entorno de desarrollo completo con un solo comando sin dependencias externas.

**Referencia TDD:** §4.2, §11.1
**Prioridad:** P0-Critical
**Estimación total:** L (1–2 días)
**Dependencias:** US-001

### Criterios de Aceptación

1. `docker compose up` levanta PostgreSQL, Dragonfly y SeaweedFS sin errores.
2. PostgreSQL es accesible en `localhost:5432` con credenciales configuradas por variable de entorno.
3. Dragonfly es accesible en `localhost:6379` (protocolo Redis-compatible).
4. SeaweedFS es accesible en `localhost:8333` (API S3-compatible) con un bucket inicial `podsync` creado automáticamente.
5. Los volúmenes de datos persisten entre reinicios de contenedores.
6. El backend NestJS puede conectarse a los tres servicios al levantarse.
7. Existe un archivo `.env.example` con todas las variables documentadas.
8. `docker compose down -v` limpia todos los datos para empezar de cero.

### Tareas

#### TASK-006: Crear Docker Compose con servicios de infraestructura

| Campo | Valor |
|-------|-------|
| **ID** | TASK-006 |
| **Tamaño** | L |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-001 |

**Especificación de implementación:**

1. Crear `docker-compose.yml` en la raíz del monorepo con los siguientes servicios:

   **PostgreSQL:**
   ```yaml
   postgres:
     image: postgres:<major-stable>-alpine  # Usar última versión major estable (e.g. 17-alpine)
     environment:
       POSTGRES_USER: ${POSTGRES_USER:-podsync}
       POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-podsync_dev}
       POSTGRES_DB: ${POSTGRES_DB:-podsync}
     ports:
       - "${POSTGRES_PORT:-5432}:5432"
     volumes:
       - postgres_data:/var/lib/postgresql/data
     healthcheck:
       test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-podsync}"]
       interval: 5s
       timeout: 5s
       retries: 5
   ```

   **Dragonfly (reemplazo de Redis):**
   ```yaml
   dragonfly:
     image: docker.dragonflydb.io/dragonflydb/dragonfly:latest
     ports:
       - "${DRAGONFLY_PORT:-6379}:6379"
     volumes:
       - dragonfly_data:/data
     healthcheck:
       test: ["CMD", "redis-cli", "ping"]
       interval: 5s
       timeout: 5s
       retries: 5
   ```

   **SeaweedFS (Master + Volume + S3 Gateway):**
   ```yaml
   seaweedfs-master:
     image: chrislusf/seaweedfs:latest
     command: "master -ip=seaweedfs-master -port=9333"
     ports:
       - "9333:9333"
     volumes:
       - seaweedfs_master_data:/data

   seaweedfs-volume:
     image: chrislusf/seaweedfs:latest
     command: "volume -mserver=seaweedfs-master:9333 -port=8080 -dir=/data"
     depends_on:
       - seaweedfs-master
     volumes:
       - seaweedfs_volume_data:/data

   seaweedfs-s3:
     image: chrislusf/seaweedfs:latest
     command: "s3 -filer=seaweedfs-filer:8888 -port=8333 -config=/etc/seaweedfs/s3.json"
     ports:
       - "${S3_PORT:-8333}:8333"
     depends_on:
       - seaweedfs-filer
     volumes:
       - ./docker/seaweedfs/s3.json:/etc/seaweedfs/s3.json:ro

   seaweedfs-filer:
     image: chrislusf/seaweedfs:latest
     command: "filer -master=seaweedfs-master:9333 -port=8888"
     depends_on:
       - seaweedfs-master
       - seaweedfs-volume
     volumes:
       - seaweedfs_filer_data:/data
   ```

2. Crear `docker/seaweedfs/s3.json` con configuración del bucket inicial:
   ```json
   {
     "identities": [
       {
         "name": "admin",
         "credentials": [
           { "accessKey": "podsync_dev_key", "secretKey": "podsync_dev_secret" }
         ],
         "actions": ["Admin", "Read", "Write", "List", "Tagging"]
       }
     ]
   }
   ```

3. Crear script `docker/seaweedfs/init-bucket.sh` para crear el bucket `podsync` al iniciar (ejecutar con `s3cmd` o `aws cli` contra el gateway S3).

4. Crear `.env.example` en la raíz:
   ```env
   # PostgreSQL
   POSTGRES_USER=podsync
   POSTGRES_PASSWORD=podsync_dev
   POSTGRES_DB=podsync
   POSTGRES_PORT=5432
   DATABASE_URL=postgresql://podsync:podsync_dev@localhost:5432/podsync

   # Dragonfly (Redis-compatible)
   DRAGONFLY_PORT=6379
   REDIS_URL=redis://localhost:6379

   # SeaweedFS (S3-compatible)
   S3_PORT=8333
   S3_ENDPOINT=http://localhost:8333
   S3_ACCESS_KEY=podsync_dev_key
   S3_SECRET_KEY=podsync_dev_secret
   S3_BUCKET=podsync

   # Auth
   JWT_SECRET=dev-secret-change-in-production
   REFRESH_TOKEN_SECRET=dev-refresh-secret-change-in-production
   AUTH_ENABLED=true

   # App
   PORT=3000
   ALLOWED_ORIGIN=http://localhost:5173
   NODE_ENV=development
   ```

5. Declarar todos los named volumes al final del `docker-compose.yml`.

**Verificación:**
- `docker compose up -d` → todos los servicios en estado `healthy` en < 30 segundos.
- `psql` puede conectar a PostgreSQL.
- `redis-cli -p 6379 ping` retorna `PONG`.
- `curl http://localhost:8333` responde (SeaweedFS S3 gateway activo).
