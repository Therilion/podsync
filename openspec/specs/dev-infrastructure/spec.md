# dev-infrastructure Specification

## Purpose
TBD - created by archiving change dev-infrastructure-docker-compose. Update Purpose after archive.
## Requirements
### Requirement: Single-command environment bootstrap

The development infrastructure SHALL allow a developer to start the full set of local data services (PostgreSQL, Dragonfly, SeaweedFS) with a single command (`docker compose up -d`) executed from the monorepo root, with no external dependencies beyond Docker Engine.

#### Scenario: Cold start with default environment

- **WHEN** a developer runs `docker compose up -d` on a machine where Docker is installed and the working directory is the monorepo root, after copying `.env.example` to `.env`
- **THEN** all required services reach a usable state (PostgreSQL and Dragonfly report `healthy`, the SeaweedFS S3 gateway responds on its configured port) within 30 seconds, excluding image-pull time on the first run

#### Scenario: Restart preserves working state

- **WHEN** the developer runs `docker compose restart` after a successful initial start
- **THEN** all services come back up healthy and previously created data (databases, keys, buckets, objects) is still present

### Requirement: PostgreSQL service

The compose stack SHALL provide a PostgreSQL service that is reachable from the host and configured entirely through environment variables defined in `.env.example`.

#### Scenario: Reachable on configured port

- **WHEN** the stack is up and the developer runs `pg_isready -h localhost -p ${POSTGRES_PORT:-5432} -U ${POSTGRES_USER:-podsync}`
- **THEN** the command exits with status 0

#### Scenario: Configured by environment variables

- **WHEN** the developer overrides `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` or `POSTGRES_PORT` in `.env` and restarts the stack from a clean volume
- **THEN** PostgreSQL starts with those values and `psql "$DATABASE_URL"` connects successfully

#### Scenario: Pinned to a stable major

- **WHEN** the `docker-compose.yml` is inspected
- **THEN** the `postgres` service uses an image tag of the form `postgres:<major>-alpine` with `<major>` being a specific stable major version (never `latest`), and the chosen major is documented in the repository `README`

### Requirement: Redis-compatible cache via Dragonfly

The compose stack SHALL provide a Redis-protocol-compatible cache service implemented with Dragonfly. The application code MUST be able to use it via standard Redis clients through the `REDIS_URL` environment variable.

#### Scenario: Responds to PING

- **WHEN** the stack is up and the developer runs `redis-cli -h localhost -p ${DRAGONFLY_PORT:-6379} ping`
- **THEN** the command returns `PONG`

#### Scenario: REDIS_URL points to Dragonfly

- **WHEN** the application reads `REDIS_URL` from `.env`
- **THEN** the URL resolves to the Dragonfly container exposed on the host port `${DRAGONFLY_PORT:-6379}` and any standard Redis client (e.g. `ioredis`) can connect and execute commands

### Requirement: S3-compatible object storage via SeaweedFS

The compose stack SHALL provide an S3-compatible object storage service implemented with SeaweedFS in a master + volume + filer + s3-gateway topology. The S3 API MUST be reachable on the host on a configurable port.

#### Scenario: S3 gateway is reachable

- **WHEN** the stack is up and the developer runs `curl -sS -o /dev/null -w '%{http_code}' http://localhost:${S3_PORT:-8333}/`
- **THEN** the gateway returns a non-5xx HTTP status code, indicating it is alive and serving the S3 API

#### Scenario: Initial bucket exists after start

- **WHEN** the stack reaches `healthy` state for the first time and the bucket-init service has finished
- **THEN** the bucket named `${S3_BUCKET:-podsync}` exists in the SeaweedFS S3 gateway and is listable using the credentials from `s3.json` / `.env` (`S3_ACCESS_KEY`, `S3_SECRET_KEY`)

#### Scenario: Bucket initialization is idempotent

- **WHEN** the developer stops and starts the stack repeatedly without removing volumes
- **THEN** the bucket-init service succeeds every time without error, never duplicating or corrupting the bucket

### Requirement: Persistent and resettable data volumes

All stateful services SHALL persist their data in named Docker volumes so that data survives container restarts. The stack MUST also support a clean reset that removes all local data.

#### Scenario: Data persists across container restart

- **WHEN** the developer writes data (a row in PostgreSQL, a key in Dragonfly, an object in SeaweedFS) and then runs `docker compose restart` or `docker compose down` followed by `docker compose up -d`
- **THEN** the previously written data is still present after the services come back up

#### Scenario: Full reset with `down -v`

- **WHEN** the developer runs `docker compose down -v`
- **THEN** all named volumes used by the stack are removed and the next `docker compose up -d` starts with empty PostgreSQL, empty Dragonfly, and a freshly recreated `${S3_BUCKET:-podsync}` bucket

### Requirement: Documented environment variables in `.env.example`

The repository root SHALL contain an `.env.example` file documenting every environment variable consumed by the compose stack and by the backend in development. The real `.env` file MUST be excluded from version control.

#### Scenario: `.env.example` covers all required keys

- **WHEN** `.env.example` is inspected
- **THEN** it contains entries (with sensible development defaults) for at minimum: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT`, `DATABASE_URL`, `DRAGONFLY_PORT`, `REDIS_URL`, `S3_PORT`, `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET`, `JWT_SECRET`, `REFRESH_TOKEN_SECRET`, `AUTH_ENABLED`, `PORT`, `ALLOWED_ORIGIN`, `NODE_ENV`

#### Scenario: `.env` is gitignored

- **WHEN** a developer creates a `.env` file at the repository root
- **THEN** `git status` does not list it as a tracked or untracked file (because `.gitignore` excludes it)

### Requirement: Backend can connect to all services

The development infrastructure SHALL be sufficient for the NestJS backend (delivered by the `backend-bootstrap` capability) to connect to PostgreSQL, Dragonfly and SeaweedFS using only the variables exposed in `.env.example`.

#### Scenario: Backend resolves all data dependencies on startup

- **WHEN** the compose stack is up and the backend is started with the variables from `.env`
- **THEN** the backend can establish a working TCP/HTTP connection to PostgreSQL (via `DATABASE_URL`), Dragonfly (via `REDIS_URL`) and the SeaweedFS S3 gateway (via `S3_ENDPOINT` with the configured access key/secret) without any additional configuration

### Requirement: Documented operational entrypoint in README

The repository `README` SHALL document how to start, verify, and reset the development infrastructure, and SHALL state which PostgreSQL major version is pinned in `docker-compose.yml`.

#### Scenario: README contains operational instructions

- **WHEN** a new developer reads the `README`
- **THEN** they find: (a) the prerequisites (Docker), (b) the commands to copy `.env.example` and run `docker compose up -d`, (c) verification commands for each service, (d) the command to fully reset (`docker compose down -v`), and (e) the pinned PostgreSQL major version

