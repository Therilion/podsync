## 1. Branch & worktree setup

- [x] 1.1 Create worktree `../podsync-feature-TASK-006-docker-compose` from branch `feature/TASK-006-docker-compose` based on `develop`
- [x] 1.2 Confirm Docker Engine / Docker Desktop is available on the dev machine and note the version in commit message context

## 2. Environment configuration

- [x] 2.1 Create `.env.example` at the repository root with sections for PostgreSQL, Dragonfly, SeaweedFS, Auth and App, covering every key listed in the `dev-infrastructure` spec (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT`, `DATABASE_URL`, `DRAGONFLY_PORT`, `REDIS_URL`, `S3_PORT`, `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET`, `JWT_SECRET`, `REFRESH_TOKEN_SECRET`, `AUTH_ENABLED`, `PORT`, `ALLOWED_ORIGIN`, `NODE_ENV`)
- [x] 2.2 Update `.gitignore` to exclude `.env` (without masking other tracked files)
- [x] 2.3 Verify locally that copying `.env.example` to `.env` produces a working configuration with default values

## 3. SeaweedFS configuration assets

- [x] 3.1 Create `docker/seaweedfs/s3.json` with one admin identity (`podsync_dev_key` / `podsync_dev_secret`) granting `Admin, Read, Write, List, Tagging`
- [x] 3.2 Create `docker/seaweedfs/init-bucket.sh` that uses `aws-cli` against `S3_ENDPOINT`, checks for the bucket via `head-bucket`, creates it only if missing, and retries with exponential backoff while the gateway is still warming up (max ~30 s)
- [x] 3.3 Make `init-bucket.sh` executable (`chmod +x`) and idempotent on repeated runs

## 4. `docker-compose.yml`

- [x] 4.1 Pick the latest stable PostgreSQL major and pin it as `postgres:<major>-alpine` (document the chosen major in the README)
- [x] 4.2 Define `postgres` service with env-driven user/password/db/port, named volume `postgres_data`, and a `pg_isready` healthcheck
- [x] 4.3 Define `dragonfly` service using the official Dragonfly image with a fixed stable tag, env-driven port, named volume `dragonfly_data`, and a `redis-cli ping` healthcheck
- [x] 4.4 Define `seaweedfs-master`, `seaweedfs-volume`, `seaweedfs-filer`, `seaweedfs-s3` services using a fixed `chrislusf/seaweedfs` tag, with named volumes `seaweedfs_master_data`, `seaweedfs_volume_data`, `seaweedfs_filer_data`, the correct `command` flags, and `depends_on` chain (master → volume/filer → s3); only expose `${S3_PORT:-8333}` to the host
- [x] 4.5 Mount `./docker/seaweedfs/s3.json` read-only into the `seaweedfs-s3` container
- [x] 4.6 Add a one-shot `seaweedfs-bucket-init` service (image `amazon/aws-cli` or equivalent) that runs `init-bucket.sh`, depends on `seaweedfs-s3`, has `restart: "no"`, and reads `S3_*` env vars
- [x] 4.7 Declare all named volumes in the top-level `volumes:` block

## 5. README documentation

- [x] 5.1 Add an "Infraestructura de desarrollo" section to the repository `README` listing prerequisites (Docker), the start command (`docker compose up -d`), the verification commands (`pg_isready`, `redis-cli ping`, `curl http://localhost:8333/`), the reset command (`docker compose down -v`), and the pinned PostgreSQL major
- [x] 5.2 Document the development credentials (`podsync_dev_*`) and warn explicitly that they MUST NOT be reused in production

## 6. Verification (TDD-style end-to-end checks)

- [x] 6.1 From a clean state, run `docker compose up -d --wait` and confirm `postgres` and `dragonfly` reach `healthy` and `seaweedfs-bucket-init` exits with status 0 within 30 s (excluding image download)
- [x] 6.2 Run `pg_isready -h localhost -p ${POSTGRES_PORT:-5432} -U ${POSTGRES_USER:-podsync}` and confirm exit code 0
- [x] 6.3 Run `redis-cli -h localhost -p ${DRAGONFLY_PORT:-6379} ping` and confirm `PONG`
- [x] 6.4 Run `curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:${S3_PORT:-8333}/` and confirm a non-5xx status
- [x] 6.5 Using `aws --endpoint-url=$S3_ENDPOINT s3 ls`, confirm the bucket `${S3_BUCKET:-podsync}` exists
- [x] 6.6 Write a probe row in PostgreSQL, a probe key in Dragonfly, and upload a probe object to the bucket; run `docker compose restart`; verify all three are still present
- [x] 6.7 Run `docker compose down -v` followed by `docker compose up -d --wait` and confirm the probes from 6.6 are gone but the bucket has been recreated empty

## 7. Commit & PR

- [ ] 7.1 Stage changes (`docker-compose.yml`, `docker/seaweedfs/*`, `.env.example`, `.gitignore`, `README.md`) and create a commit using the `git-commit` skill (Conventional Commits, English, e.g. `feat(infra): add docker compose stack for postgres, dragonfly and seaweedfs`)
- [ ] 7.2 Push the feature branch and open a PR targeting `develop` linking US-002 / TASK-006
- [ ] 7.3 After PR approval & merge, archive the OpenSpec change with `/opsx:archive`
