# US-003 — Esquema de Base de Datos Inicial

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** desarrollador,
> **quiero** tener el esquema de base de datos definido con Prisma ORM incluyendo las tablas `users`, `rooms`, `participants`, `room_settings` y `recording_sessions`,
> **para** poder persistir las entidades principales del sistema con migraciones versionadas y tipado automático.

**Referencia TDD:** §6.6 (Modelo de Datos), §11.1
**Prioridad:** P0-Critical
**Estimación total:** L (1–2 días)
**Dependencias:** US-002

### Criterios de Aceptación

1. El archivo `prisma/schema.prisma` define las tablas `users`, `rooms`, `participants`, `room_settings` y `recording_sessions` con todos los campos, tipos y relaciones especificados en §6.6 del TDD.
2. `pnpm prisma migrate dev` genera y aplica la migración inicial sin errores.
3. `pnpm prisma generate` genera el cliente Prisma sin errores y los tipos son accesibles desde `apps/api`.
4. `rooms.status` usa un enum PostgreSQL con valores `active` y `closed`.
5. `participants.role` usa un enum con valores `host` y `guest`.
6. `participants.status` usa un enum con valores `connected`, `disconnected` y `left`.
7. `recording_sessions.status` usa un enum con valores `recording`, `grace_period`, `processing`, `completed` y `failed`.
8. `rooms.owner_user_id` es nullable y tiene FK a `users.id`.
9. `participants.user_id` es nullable y tiene FK a `users.id`.
10. `room_settings.room_id` tiene una relación 1:1 con unique constraint.
11. Los campos de timestamps (`created_at`, `joined_at`, etc.) tienen default `now()`.
12. Existe un test de integración que verifica que el esquema se aplica correctamente contra la base de datos.

### Tareas

#### TASK-007: Definir esquema Prisma con tablas del Hito 1

| Campo | Valor |
|-------|-------|
| **ID** | TASK-007 |
| **Tamaño** | L |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-006 |

**Especificación de implementación:**

1. Instalar Prisma en `apps/api`:
   ```bash
   pnpm add prisma @prisma/client
   pnpm add -D prisma
   ```

2. Crear `apps/api/prisma/schema.prisma`:

   ```prisma
   generator client {
     provider = "prisma-client-js"
   }

   datasource db {
     provider = "postgresql"
     url      = env("DATABASE_URL")
   }

   // --- Enums ---

   enum RoomStatus {
     active
     closed
   }

   enum ParticipantRole {
     host
     guest
   }

   enum ParticipantStatus {
     connected
     disconnected
     left
   }

   enum RecordingSessionStatus {
     recording
     grace_period
     processing
     completed
     failed
   }

   enum ExportFormat {
     flac
     wav
     mp3
   }

   // --- Models ---

   model User {
     id           String   @id @default(uuid()) @db.Uuid
     email        String   @unique
     passwordHash String   @map("password_hash")
     createdAt    DateTime @default(now()) @map("created_at")

     rooms        Room[]
     participants Participant[]

     @@map("users")
   }

   model Room {
     id          String     @id @default(uuid()) @db.Uuid
     code        String     @unique @db.VarChar(8)
     status      RoomStatus @default(active)
     ownerUserId String?    @map("owner_user_id") @db.Uuid
     ttlJobId    String?    @map("ttl_job_id") @db.VarChar(255)
     createdAt   DateTime   @default(now()) @map("created_at")

     owner       User?        @relation(fields: [ownerUserId], references: [id])
     settings    RoomSettings?
     participants Participant[]
     sessions    RecordingSession[]

     @@map("rooms")
   }

   model RoomSettings {
     id                     String       @id @default(uuid()) @db.Uuid
     roomId                 String       @unique @map("room_id") @db.Uuid
     chunkIntervalMs        Int          @default(5000) @map("chunk_interval_ms")
     gracePeriodMs          Int          @default(300000) @map("grace_period_ms")
     maxParticipants        Int          @default(5) @map("max_participants")
     exportFormat           ExportFormat @default(flac) @map("export_format")
     maxRoomDurationMs      Int?         @default(7200000) @map("max_room_duration_ms")
     maxRecordingDurationMs Int?         @default(3600000) @map("max_recording_duration_ms")

     room Room @relation(fields: [roomId], references: [id], onDelete: Cascade)

     @@map("room_settings")
   }

   model Participant {
     id          String            @id @default(uuid()) @db.Uuid
     roomId      String            @map("room_id") @db.Uuid
     userId      String?           @map("user_id") @db.Uuid
     displayName String            @map("display_name") @db.VarChar(100)
     email       String?           @db.VarChar(255)
     role        ParticipantRole
     status      ParticipantStatus @default(connected)
     joinedAt    DateTime          @default(now()) @map("joined_at")

     room Room  @relation(fields: [roomId], references: [id], onDelete: Cascade)
     user User? @relation(fields: [userId], references: [id])

     @@map("participants")
   }

   model RecordingSession {
     id         String                 @id @default(uuid()) @db.Uuid
     roomId     String                 @map("room_id") @db.Uuid
     startedAt  DateTime               @default(now()) @map("started_at")
     endedAt    DateTime?              @map("ended_at")
     status     RecordingSessionStatus @default(recording)
     limitJobId String?                @map("limit_job_id") @db.VarChar(255)

     room Room @relation(fields: [roomId], references: [id], onDelete: Cascade)

     @@map("recording_sessions")
   }
   ```

3. Crear módulo `PrismaModule` en NestJS:
   - `apps/api/src/prisma/prisma.service.ts`: Extiende `PrismaClient` e implementa `OnModuleInit` y `OnModuleDestroy`.
   - `apps/api/src/prisma/prisma.module.ts`: Módulo global (`@Global()`) que exporta `PrismaService`.

4. Ejecutar `pnpm prisma migrate dev --name init` para generar la primera migración.

**Tests TDD:**

- **Red (unit):** Test para `PrismaService` que verifica que `onModuleInit` llama a `$connect`.
- **Green:** Implementar `PrismaService` con `$connect` en `onModuleInit`.
- **Red (integration):** Test con testcontainers que levanta PostgreSQL, ejecuta la migración y verifica que puede crear/leer un `User`.
- **Green:** Verificar que el esquema se aplica correctamente.

```typescript
// prisma.service.spec.ts (unit)
describe('PrismaService', () => {
  it('should connect on module init', async () => {
    const service = new PrismaService();
    jest.spyOn(service, '$connect').mockResolvedValue();
    await service.onModuleInit();
    expect(service.$connect).toHaveBeenCalled();
  });
});
```

**Verificación:** `pnpm prisma migrate status` muestra migración aplicada. `pnpm prisma studio` abre la UI de Prisma mostrando todas las tablas.
