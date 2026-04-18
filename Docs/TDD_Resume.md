# AGENTS.md — PodSync

> **Documento de contexto para agentes IA de desarrollo.**
> Resumen denso y operativo del TDD v1.6 (Abril 2026). Diseñado para cargarse como contexto al inicio de cada tarea.
>
> **Fuente de verdad:** `docs/PodSync_Documento_Tecnico_v1_6.md` (§N referencia sus secciones).
> **Plan del hito actual:** `docs/H1_Historias_de_Usuario.md` (IDs `US-###`, `TASK-###`).
> Si este documento y el TDD divergen, **gana el TDD**. Abre PR para sincronizar.

---

## 1. Qué es PodSync (una línea)

Plataforma web para grabación remota de podcasts: cada participante **habla en vivo vía SFU (mediasoup)** y **graba localmente** con MediaRecorder; los chunks se suben incrementalmente al servidor vía WebSocket y se procesan en pistas individuales + mezcla final.

**Problema que resuelve:** Discord+OBS produce una sola pista mezclada; PodSync produce N pistas independientes, limpias, editables.

---

## 2. Invariantes del sistema (no romper)

Estas reglas atraviesan todo el código. Una PR que las viole debe rechazarse.

| #    | Invariante                                                                                                                                                          | Por qué                      |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| I-1  | **El audio original nunca se destruye.** Reducción de ruido y normalización generan *variantes adicionales*, no reemplazos.                                         | §6.5. Requisito de producto. |
| I-2  | **Identidad asimétrica host/guest es inmutable.** Host = cuenta persistente (Passport + argon2). Guest = JWT efímero, sin registro.                                 | §7, ADR-002.                 |
| I-3  | **Los límites de tiempo se enforzan SOLO en servidor.** El cliente no es fuente de verdad. Jobs delayed en BullMQ con recovery tras restart.                        | §6.4, §6.4.5.                |
| I-4  | **Una sala solo puede tener UNA sesión de grabación activa** (`recording` o `grace_period`). Validación con lock pesimista. Múltiples sesiones son *secuenciales*.  | §6.2.1, ADR-001.             |
| I-5  | **Toda interacción con almacenamiento pasa por `StoragePort`.** No importar clientes S3 directamente en la lógica de negocio.                                       | §6.2.3.                      |
| I-6  | **`timestamp_ms` en el header de chunks es relativo al inicio de la sesión**, no epoch. 4 bytes uint32 BE.                                                          | §6.1.2.                      |
| I-7  | **Chunks validan `session_id`**: un chunk de sesión A nunca se acepta para sesión B.                                                                                | §11.2.                       |
| I-8  | **`HostGuard` es el único punto donde se decide si alguien es host.** Encapsulado para evolución futura (planes comerciales).                                       | §7.7.                        |
| I-9  | **Metodología TDD estricta:** Red → Green → Refactor. Los tests se escriben **antes** de la implementación.                                                         | H1 doc.                      |
| I-10 | **Política de versiones:** Las versiones en docs son referenciales (Abril 2026). Usar la **última estable/LTS** al implementar, salvo incompatibilidad documentada. | H1 doc.                      |

---

## 3. Stack tecnológico (§4.2)

| Capa                  | Tecnología                                        | Notas                                           |
| --------------------- | ------------------------------------------------- | ----------------------------------------------- |
| Frontend              | React 19 + TypeScript + Vite                      | `apps/web`                                      |
| UI                    | Tailwind CSS + shadcn/ui                          | —                                               |
| Backend API/WS        | NestJS + **Fastify adapter** + @nestjs/websockets | `apps/api`. No Express.                         |
| Backend procesamiento | Python + FFmpeg                                   | `apps/worker` (servicio separado)               |
| Auth                  | Passport.js (`@nestjs/passport`) + argon2         | LocalStrategy + JwtStrategy                     |
| Live comms            | mediasoup (SFU)                                   | Integrado en proceso NestJS, comunicado por IPC |
| WebSocket             | NestJS Gateway (`ws`)                             | —                                               |
| Storage               | SeaweedFS (S3-compatible) vía `StoragePort`       | Dev y prod                                      |
| DB                    | PostgreSQL + Prisma ORM                           | —                                               |
| Queue                 | BullMQ + **Dragonfly** (Redis-compatible)         | Dragonfly, no Redis                             |
| Bridge cola→worker    | HTTP (NestJS consumer → Python REST)              | No gRPC, no subprocess                          |
| Audio processing      | FFmpeg + RNNoise (WASM)                           | `arnndn` filter                                 |
| Reverse proxy         | Caddy                                             | SSL automático Let's Encrypt                    |
| Monorepo              | Turborepo + pnpm + Corepack                       | `packageManager` fijado en `package.json`       |
| Contenerización       | Docker + Docker Compose                           |                                                 |
| CI/CD                 | GitHub Actions                                    |                                                 |
| Logging               | pino (JSON structured)                            |                                                 |
| Metrics               | Prometheus-compatible `/metrics`                  |                                                 |

**No sustituir tecnologías sin ADR aprobado.** Si hay problema serio con una elección, abrir issue flagueando riesgo, no cambiarla.

---

## 4. Arquitectura (§5)

```
Cliente (Browser)
├── mediasoup-client SDK     ← live comms (1 uplink, N-1 downlinks)
├── MediaRecorder            ← grabación local (Opus en WebM)
├── Web Worker               ← buffer + envío de chunks
└── WebSocket                ← signaling + chunks binarios

Servidor NestJS (apps/api)
├── AuthModule               ← Passport + argon2 + JWT
├── UsersModule              ← cuentas host
├── RoomsModule              ← salas, settings, TTL
├── RecordingModule          ← sesiones, límites, estados
├── SignalingModule          ← WS Gateway
├── ChunksModule             ← recepción chunks + ACK
├── MediaModule              ← wrapper mediasoup
└── PrismaModule (@Global)

mediasoup Worker              ← proceso child de NestJS, IPC
Worker Python (apps/worker)   ← REST: POST /api/process, callback /api/internal/processing-status

Infra
├── PostgreSQL               ← metadatos + users
├── SeaweedFS (S3)           ← chunks + procesados
├── Dragonfly                ← BullMQ backend
└── Caddy                    ← TLS + reverse proxy
```

---

## 5. Layout del monorepo

```
.
├── apps/
│   ├── web/                 # React + Vite
│   ├── api/                 # NestJS + Fastify
│   │   ├── prisma/
│   │   │   ├── schema.prisma
│   │   │   └── seed.ts
│   │   └── src/
│   │       ├── auth/
│   │       ├── users/
│   │       ├── rooms/
│   │       ├── recording/
│   │       ├── signaling/
│   │       ├── chunks/
│   │       ├── media/
│   │       └── prisma/
│   └── worker/              # Python + FFmpeg (H2+)
├── packages/
│   └── shared/              # tipos TS compartidos web↔api
├── docker/
│   ├── seaweedfs/
│   └── …
├── docker-compose.yml
├── turbo.json
├── pnpm-workspace.yaml
├── package.json             # "packageManager": "pnpm@<latest>"
├── AGENTS.md                # ← este documento
└── docs/
    ├── PodSync_Documento_Tecnico_v1_6.md
    └── H1_Historias_de_Usuario.md
```

**Scripts raíz esperados:** `dev`, `build`, `lint`, `format`, `test`, `seed:admin`.

---

## 6. Modelo de datos (§6.6) — mínimo mental

### Tablas (Hito 1)

```
users (id UUID PK, email UNIQUE, password_hash, created_at)
  └─ rooms (owner_user_id UUID? FK → users)           ← nullable para dev mode
       ├─ room_settings (1:1)
       │    · chunk_interval_ms=5000
       │    · grace_period_ms=300000
       │    · max_participants=5
       │    · export_format=flac
       │    · max_room_duration_ms=7200000            ← 2h default
       │    · max_recording_duration_ms=3600000       ← 1h default
       ├─ participants (user_id UUID? FK → users)      ← nullable para guests
       │    · role: host|guest
       │    · status: connected|disconnected|left
       └─ recording_sessions (1:N secuenciales)
            · status: recording|grace_period|processing|completed|failed
            · limit_job_id VARCHAR?                    ← BullMQ jobId cancelable
```

### Tablas adicionales (Hitos 2+)

- `refresh_tokens` (hash, userId, expiresAt) — rotación de refresh tokens.
- `audio_chunks` (seq_num, ts_start_ms, ts_end_ms, s3_key, status: received|processing|irrecoverable).
- `participant_avatars` (idle + speaking image keys).
- `processing_presets` (1:1 con session, editable por host pre-procesamiento).
- `vad_events`, `timestamp_marks` — metadatos de edición.
- `processed_tracks` (variant: raw|denoised|mix).
- `notifications`.

**Enums PostgreSQL obligatorios:** `RoomStatus`, `ParticipantRole`, `ParticipantStatus`, `RecordingSessionStatus`, `ExportFormat`.

### Convenciones Prisma
- IDs: `UUID`, `@default(uuid()) @db.Uuid`.
- Timestamps: `DateTime @default(now()) @map("snake_case")`.
- Cascada: `onDelete: Cascade` en children obvias (settings, participants, sessions).
- `@@map("snake_case")` para todas las tablas (código TS en camelCase, DB en snake_case).

---

## 7. Auth — asimetría host/guest (§7)

### Host (persistente)
- Registro: `POST /api/auth/register` `{email, password}` → argon2 (`memoryCost: 65536, timeCost: 3, parallelism: 4`).
- Login: `POST /api/auth/login` → JWT 7 días + refresh token 30 días en cookie `httpOnly, secure, sameSite: strict, path=/api/auth/refresh`.
- Refresh: `POST /api/auth/refresh` → **rota** refresh token (invalida anterior, emite nuevo).
- Me: `GET /api/auth/me` → `{userId, email, createdAt}`.
- JWT payload: `{sub: userId, email, type: "host", iat, exp}`.

### Guest (efímero)
- Sin registro. Join: `POST /api/rooms/:id/join` `{displayName, email?}` → JWT 24h, sin refresh.
- JWT payload: `{sub: participantId, type: "guest", role: "guest", roomId, displayName}`.
- Almacenar JWT en `sessionStorage` durante grabación activa (para reconexión).

### Rate limits (§8)
| Endpoint              | Límite                                                 |
| --------------------- | ------------------------------------------------------ |
| `/auth/register`      | 3/hora por IP                                          |
| `/auth/login`         | 10/15 min por email, lockout 30 min                    |
| `/rooms` (POST)       | 5/hora por usuario auth                                |
| WebSocket connections | 10 simultáneas por IP                                  |
| Chunks                | 1 cada 3s por participante, 3 violaciones → disconnect |
| Mensajes signaling    | 20/seg, excedentes ignoradas                           |

### Desarrollo local
- `AUTH_ENABLED=false` desactiva auth completa. `POST /api/rooms` sin JWT → `owner_user_id = null`.
- Log `warn` al iniciar: `"⚠️ Auth disabled — development mode only"`.
- **Nunca** en producción. Default `true`.

### `HostGuard` (§7.7) — punto único de autorización
```typescript
if (jwt.type === 'host') return roomsService.isOwner(jwt.sub, roomId);
return jwt.role === 'host'; // guest JWT path, siempre false hoy
```
Futuro: aquí también se valida plan comercial. No duplicar esta lógica en otros sitios.

### Matriz de permisos (§7.6 resumida)

| Acción                         | Host  | Guest |
| ------------------------------ | :---: | :---: |
| Registrar / Login              |   ✅   |   —   |
| Crear sala                     |   ✅   |   ❌   |
| Unirse a sala                  |   —   |   ✅   |
| Iniciar/finalizar grabación    |   ✅   |   ❌   |
| Configurar sala / preset       |   ✅   |   ❌   |
| Cerrar sala                    |   ✅   |   ❌   |
| Mutear/desmutear propio        |   ✅   |   ✅   |
| Levantar mano, marca de tiempo |   ✅   |   ✅   |
| Sugerir finalización           |   ❌   |   ✅   |
| Descargar pistas               |   ✅   |   ✅   |

---

## 8. Protocolo de chunks (§6.1.2, §6.2.3)

**Formato binario por WebSocket:**

```
┌─────────────────────────────────────────────────────┐
│ Header = 40 bytes                                   │
├──────────────────┬────────┬─────────────────────────┤
│ session_id       │ 16 B   │ UUID binario            │
│ participant_id   │ 16 B   │ UUID binario            │
│ sequence_number  │ 4 B    │ uint32 big-endian       │
│ timestamp_ms     │ 4 B    │ uint32 BE, rel. inicio  │
├──────────────────┴────────┴─────────────────────────┤
│ Payload: WebM/Opus bytes (≤ 5 MB)                   │
└─────────────────────────────────────────────────────┘
```

**Claves S3:** `sessions/{session_id}/participants/{participant_id}/chunks/{sequence_number}.webm`

**ACK:** Servidor responde `chunk:ack` con `sequence_number`. Cliente reintenta 3× con backoff exponencial si no hay ACK en 5s.

**Buffer cliente:** Hasta 60 chunks (~5 min) si se pierde la conexión; se drenan al reconectar.

**`timestamp_ms = 0`** es el instante en que el cliente recibe `recording:start`. Cada chunk: `Date.now() - recordingStartTime`. No hay sincronización de relojes entre clientes.

---

## 9. Ciclo de vida de una sesión de grabación

```
         ┌─────────────────────────────────────────────────┐
         │                                                 │
    recording/start (host)                                 │
         │                                                 │
         ▼                                                 │
    ┌──────────┐   stop / time-expired    ┌─────────────┐ │
    │recording │─────────────────────────▶│grace_period │ │
    └──────────┘                          └──────┬──────┘ │
                                                 │        │
                                        grace_period_ms   │
                                                 │        │
                                                 ▼        │
                                          ┌──────────┐    │
                                          │processing│    │
                                          └─────┬────┘    │
                                                │         │
                                   ┌────────────┴──────┐  │
                                   ▼                   ▼  │
                             ┌─────────┐          ┌──────────┐
                             │completed│          │  failed  │
                             └─────────┘          └──────────┘
                                   │
                          (room puede iniciar sesión N+1) ◀┘
```

**Validaciones críticas al `recording:start`:**
1. JWT válido + `HostGuard` OK.
2. No existe sesión en `recording` ni `grace_period` (query con lock pesimista).
3. Room TTL restante > 5 min.
4. `max_recording_duration_ms` ≤ hard limit global.
5. Encolar BullMQ delayed job con `max_recording_duration_ms` de delay → guardar `jobId` en `recording_sessions.limit_job_id`.

**Al stop/expiración:** cancelar `limit_job_id` → status `grace_period` → tras `grace_period_ms` → `processing` → encolar job de worker Python → callback → `completed`/`failed`.

---

## 10. Delayed jobs + recovery (§6.4, §6.4.5)

**Dos jobs delayed en BullMQ:**
| Job             | Se crea al        | Delay                       | ID guardado en                    | Cancelable al      |
| --------------- | ----------------- | --------------------------- | --------------------------------- | ------------------ |
| Room TTL        | Crear sala        | `max_room_duration_ms`      | `rooms.ttl_job_id`                | Cerrar sala manual |
| Recording limit | Iniciar grabación | `max_recording_duration_ms` | `recording_sessions.limit_job_id` | Stop manual        |

**Warnings al cliente (5 min antes):** `room:time-warning`, `recording:time-warning`.
**Expiración:** `room:time-expired`, `recording:time-expired`.

**Recovery al boot de NestJS (OBLIGATORIO):**
1. Query `SELECT * FROM rooms WHERE status='active' AND ttl_job_id IS NOT NULL`.
2. Query `SELECT * FROM recording_sessions WHERE status IN ('recording','grace_period') AND limit_job_id IS NOT NULL`.
3. Para cada uno: verificar si job existe en BullMQ. Si no: recalcular delay restante, reprogramar. Si ya expiró: ejecutar acción inmediata.
4. Log `info`: `{jobs_reprogrammed, jobs_expired}`.

**Hard limits globales (env):** `MAX_ROOM_DURATION_HARD_LIMIT`, `MAX_RECORDING_DURATION_HARD_LIMIT`. Techo absoluto; `room_settings` nunca puede superarlos. (Futuro: reemplazados por plan comercial.)

---

## 11. Catálogo de eventos WebSocket (§6.2.2)

### Sala
| Evento                    | Dir.  | Notas                         |
| ------------------------- | :---: | ----------------------------- |
| `room:join`               |  C→S  | Incluye `token` (JWT)         |
| `room:leave`              |  C→S  |                               |
| `room:participant-joined` |  S→C  | Broadcast                     |
| `room:participant-left`   |  S→C  | Broadcast                     |
| `room:time-warning`       |  S→C  | 5 min antes de TTL, broadcast |
| `room:time-expired`       |  S→C  | TTL alcanzado                 |

### Grabación
| Evento                   |  Dir.  | Notas                       |
| ------------------------ | :----: | --------------------------- |
| `recording:countdown`    |  S→C   | Cuenta regresiva start/stop |
| `recording:start`        |  S→C   | Orden a MediaRecorder       |
| `recording:stop`         |  S→C   | Detener + enviar restantes  |
| `recording:time-warning` | S→Host | 5 min antes del límite      |
| `recording:time-expired` |  S→C   | Stop automático             |
| `chunk:data`             |  C→S   | **Binario**, ver §8 arriba  |
| `chunk:ack`              |  S→C   | `{sequence_number}`         |

### Mediasoup
| Evento                       | Dir.  |
| ---------------------------- | :---: |
| `media:get-rtp-capabilities` |  C→S  |
| `media:create-transport`     |  C→S  |
| `media:transport-connect`    |  C↔S  |
| `media:produce`              |  C→S  |
| `media:consume`              |  S→C  |
| `media:new-producer`         |  S→C  |
| `media:producer-closed`      |  S→C  |

### UX / VAD
| Evento              |   Dir.    |
| ------------------- | :-------: |
| `ui:hand-raise`     |  C↔Todos  |
| `ui:suggest-end`    |  C→Host   |
| `ui:timestamp-mark` |    C→S    |
| `vad:state`         | C→S→Todos |

---

## 12. Variables de entorno

```env
# --- PostgreSQL ---
POSTGRES_USER=podsync
POSTGRES_PASSWORD=podsync_dev
POSTGRES_DB=podsync
POSTGRES_PORT=5432
DATABASE_URL=postgresql://podsync:podsync_dev@localhost:5432/podsync

# --- Dragonfly (Redis-compatible) ---
DRAGONFLY_PORT=6379
REDIS_URL=redis://localhost:6379

# --- SeaweedFS (S3) ---
S3_PORT=8333
S3_ENDPOINT=http://localhost:8333
S3_ACCESS_KEY=podsync_dev_key
S3_SECRET_KEY=podsync_dev_secret
S3_BUCKET=podsync

# --- Auth ---
JWT_SECRET=dev-secret-change-in-production
REFRESH_TOKEN_SECRET=dev-refresh-secret-change-in-production
AUTH_ENABLED=true

# --- Hard limits (ms) ---
MAX_ROOM_DURATION_HARD_LIMIT=14400000      # 4h
MAX_RECORDING_DURATION_HARD_LIMIT=7200000  # 2h

# --- App ---
PORT=3000
ALLOWED_ORIGIN=http://localhost:5173
NODE_ENV=development

# --- Seed (opcional) ---
SEED_ADMIN_EMAIL=admin@podsync.dev
SEED_ADMIN_PASSWORD=admin123456
```

**Secretos:** nunca en código ni en `docker-compose.yml` de prod. Usar gestor de secretos del entorno de deploy.

---

## 13. Roadmap de hitos (§11)

| #      | Hito                                            | Dur.    |    Estado    |
| ------ | ----------------------------------------------- | ------- | :----------: |
| **H1** | Infraestructura, Auth y SFU                     | 5–6 sem | 🟢 **ACTUAL** |
| H2     | Grabación + chunks + multi-sesión (**MVP**)     | 5–6 sem |      ⚪       |
| H3     | Resiliencia y reconexiones                      | 3–4 sem |      ⚪       |
| H4     | Interacción UX (avatares, warnings, VAD)        | 2–3 sem |      ⚪       |
| H5     | Procesamiento avanzado + notificaciones         | 3–4 sem |      ⚪       |
| H6     | RNNoise cliente + optimización + observabilidad | 2–3 sem |      ⚪       |
| H7     | Despliegue + lanzamiento                        | 2–3 sem |      ⚪       |

**Timeline total:** ~22–29 semanas (5.5–8 meses, 1 dev).

**Hito 1 — scope concreto:** US-001 a US-017 (29 tareas). Ruta crítica ~5 sem. Ver `docs/H1_Historias_de_Usuario.md`. Entregable: host se registra, crea sala, guests se unen, hablan en tiempo real vía SFU, con monorepo + Docker Compose funcionales.

---

## 14. Convenciones de código

### TypeScript
- `strict: true` en `tsconfig.base.json`.
- `ValidationPipe` global con `whitelist: true, forbidNonWhitelisted: true`.
- DTOs con `class-validator` (`@IsEmail`, `@MinLength`, etc.).
- Path aliases configurados en todos los workspaces.
- Tipos compartidos web↔api → `packages/shared`.

### Nomenclatura
- **DB:** `snake_case` (columnas y tablas).
- **TS:** `camelCase` (propiedades), `PascalCase` (clases/tipos/enums).
- **Prisma:** modelo `PascalCase`, `@map("snake_case")` en campos y `@@map` en tablas.
- **Eventos WS:** `namespace:action` kebab (ej. `room:participant-joined`).
- **Variables env:** `SCREAMING_SNAKE_CASE`.
- **Tests:** `*.spec.ts` (unit), `*.e2e-spec.ts` (e2e).
- **IDs de historias:** `US-###`, tareas `TASK-###`.

### NestJS
- Un módulo por dominio. `PrismaModule` es `@Global()`.
- Guards por comportamiento (`JwtAuthGuard`, `HostGuard`), no por endpoint.
- Controllers delgados; lógica en Services.
- Nunca inyectar `PrismaService` en Controllers (solo en Services).

### Git
- Commits convencionales: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`.
- Una PR = una historia (o tarea si es grande). Referenciar `US-###` o `TASK-###` en el título.

---

## 15. Testing (§9)

### Niveles
| Nivel       | Herramientas                                      | Cuándo              |
| ----------- | ------------------------------------------------- | ------------------- |
| Unit        | Jest (NestJS), pytest (worker)                    | Cada PR             |
| Integration | Jest + Supertest + testcontainers (PG, Dragonfly) | Cada PR             |
| E2E         | Playwright (multi-tab)                            | Merge a `main`      |
| Load        | k6 o Artillery                                    | Pre-release (H6–H7) |

### Cobertura mínima
- Unit: **≥ 80%** en services y utils.
- Integration: **100%** de endpoints REST y eventos WS del flujo crítico.
- E2E: ≥ 3 flujos (happy path, reconexión, 5 participantes).

### Escenarios críticos obligatorios (§9.2)
- Autenticación: registro, login OK/KO, lockout, refresh, JWT expirado.
- Asimetría: guest intenta crear sala → rechazado; host ajeno → rechazado.
- Desconexión durante grabación → reconexión y drenado de buffer.
- Buffer overflow cliente (60 chunks sin conexión).
- Chunks fuera de orden → worker reordena por `sequence_number`.
- Protocolo binario: edge cases (uint32 max, UUIDs con bytes nulos).
- Múltiples sesiones secuenciales por sala (chunks de S1 no contaminan S2).
- Sesión activa única: dos `recording/start` simultáneos → solo uno OK, otro 409.
- Room TTL con grabación activa → flujo completo time-expired → stop → grace → processing → close.
- **Recovery de delayed jobs:** matar NestJS, reiniciar → jobs reprogramados.

### Ciclo TDD estricto
1. **Red:** escribir test que falla.
2. **Green:** mínima implementación para pasar.
3. **Refactor:** limpieza sin romper tests.

---

## 16. Observabilidad (§10)

### Logging (pino, JSON)
Campos mínimos por log: `timestamp, level, service, request_id|session_id, participant_id?, user_id?`.

Eventos críticos a loggear (ver §10.1 para lista completa): registro/login (éxito/fallo), chunk recibido, participante des/reconectado, backpressure violation, warnings y expiraciones de tiempo, recovery de jobs, procesamiento start/end/fail, `AUTH_ENABLED=false` warning al boot.

### Métricas (Prometheus `/metrics`)
`podsync_active_rooms`, `podsync_active_participants`, `podsync_registered_users_total`, `podsync_auth_login_total{result}`, `podsync_chunks_received_total`, `podsync_chunks_bytes_total`, `podsync_chunk_latency_ms`, `podsync_ws_connections_total`, `podsync_ws_disconnections_total`, `podsync_processing_duration_ms`, `podsync_processing_queue_size`, `podsync_mediasoup_transports_active`, `podsync_room_ttl_expirations_total`, `podsync_recording_limit_expirations_total`.

### Health checks
- `GET /health` — API up.
- `GET /health/ready` — PG + Dragonfly + SeaweedFS + mediasoup worker activos.
- `GET /health/worker` — Python worker OK + acceso S3.

### Alertas críticas
- `processing_queue_size > 10` por > 5 min → worker saturado.
- `ws_disconnections` spike > 50%/min → problema de red.
- Health check fallido > 30s.
- Tasa HTTP 5xx > 1%.
- `auth_login_total{result=failure}` spike → posible brute force.

---

## 17. Anti-patrones (NO hacer)

- ❌ Usar Express en lugar del Fastify adapter en NestJS.
- ❌ Validar límites de tiempo en el cliente como fuente de verdad.
- ❌ Permitir que chunks de sesión A se acepten en sesión B (siempre validar `session_id`).
- ❌ Destruir/sobrescribir el audio crudo en post-procesamiento.
- ❌ Importar el cliente S3 directamente en Services — usar `StoragePort`.
- ❌ Guardar passwords en plaintext o con bcrypt "porque es más simple" (usar argon2id con los parámetros definidos).
- ❌ Duplicar la lógica de "¿es host?" fuera de `HostGuard`.
- ❌ Meter secretos en `docker-compose.yml` de producción.
- ❌ Asumir que el `timestamp_ms` del chunk es epoch (es relativo al inicio de sesión).
- ❌ Usar JWT de guest sin `sessionStorage` durante grabación (rompe reconexión).
- ❌ Implementar sin test primero (viola TDD del proyecto).
- ❌ Hard-codear versiones cuando el docs dice "latest stable" (salvo imágenes Docker, donde se usa major version tag).
- ❌ Usar bullet points de una sola palabra o hacer tablas triviales — priorizar lectura fluida en docs humanos.

---

## 18. Glosario

| Término                        | Significado                                                                                                 |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| **SFU**                        | Selective Forwarding Unit — servidor que recibe 1 uplink y distribuye N-1 downlinks (mediasoup).            |
| **Chunk**                      | Fragmento WebM/Opus de 5–10s generado por MediaRecorder.                                                    |
| **Sesión (recording session)** | Una grabación individual dentro de una sala. Una sala tiene 1..N sesiones secuenciales.                     |
| **Grace period**               | Ventana (default 5 min) tras `stop` para recibir chunks pendientes antes de procesar.                       |
| **Host**                       | Usuario con cuenta persistente que crea salas. Auth con email+password+argon2.                              |
| **Guest**                      | Invitado efímero con JWT de 24h, sin registro.                                                              |
| **Producer / Consumer**        | Objetos mediasoup: Producer = envía, Consumer = recibe. Cada participante tiene 1 Producer y N-1 Consumers. |
| **VAD**                        | Voice Activity Detection — detección de habla vs silencio.                                                  |
| **Preset de procesamiento**    | Config por sesión: noise reduction, normalize LUFS, export format.                                          |
| **`StoragePort`**              | Interface que abstrae operaciones S3 (upload, download, presign, delete).                                   |
| **Room TTL**                   | Time-to-live de la sala (`max_room_duration_ms`).                                                           |
| **Recording limit**            | Tiempo máximo de una sesión individual (`max_recording_duration_ms`).                                       |
| **Hard limit**                 | Techo absoluto global configurado por env var; ningún `room_settings` puede excederlo.                      |

---

## 19. Para iteraciones futuras (§13, fuera del MVP)

No implementar ahora a menos que se abra ADR: OAuth hosts, verificación email, planes comerciales, Keycloak/Casdoor, cuenta opcional guests, avatares multi-frame, generación de video, app móvil, captura de video, transcripción Whisper, chat de texto, export DAW, grabación programada, panel admin, migración S3/R2, retención automática.

---

## 20. Cómo pedir cambios al TDD

1. Abrir issue con título `[TDD] <cambio propuesto>`.
2. Justificar con trade-offs (pros/cons, impacto en timeline, secciones afectadas).
3. Si se aprueba → crear `ADR-NNN.md` con formato Context → Decision → Consequences.
4. Actualizar TDD (nuevo `vX.Y`) y changelog.
5. Sincronizar este `AGENTS.md`.

**Formato ADR canónico:**
```markdown
# ADR-NNN: <Título corto>
## Contexto
## Decisión
## Consecuencias
### Positivas / Negativas / Neutras
## Alternativas consideradas
## Referencias (secciones del TDD afectadas)
```

---

## 21. Referencia rápida — secciones del TDD

| Necesito saber…                 | Ir a                        |
| ------------------------------- | --------------------------- |
| Por qué elegimos X tecnología   | §4.1 (análisis comparativo) |
| Stack completo                  | §4.2                        |
| Diagrama de componentes         | §5.2                        |
| Flujo de datos E2E              | §5.3                        |
| Cliente (MediaRecorder, buffer) | §6.1                        |
| API REST endpoints              | §6.2.1                      |
| WebSocket events                | §6.2.2                      |
| Chunk storage (S3 keys)         | §6.2.3                      |
| Backpressure WebSocket          | §6.2.4                      |
| Worker Python + bridge          | §6.3                        |
| Delayed jobs + recovery         | §6.4 / §6.4.5               |
| Reducción de ruido (2 niveles)  | §6.5                        |
| Modelo de datos completo        | §6.6                        |
| Flujo de auth detallado         | §7                          |
| HostGuard encapsulado           | §7.7                        |
| Seguridad + rate limits         | §8                          |
| Testing                         | §9                          |
| Logging + metrics + alerts      | §10                         |
| Plan por hitos                  | §11                         |
| Trazabilidad RF/RNF → hitos     | §12                         |

---

*Última sincronización con TDD: v1.6 (Abril 2026). Si este archivo tiene más de un hito de antigüedad, es probable que esté desactualizado.*
