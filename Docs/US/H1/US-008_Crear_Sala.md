# US-008 — Creación de Sala por Host Autenticado

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** host autenticado,
> **quiero** crear una sala de podcast con un código de invitación único,
> **para** poder invitar participantes a una sesión de grabación.

**Referencia TDD:** §7.4 (Creación de Sala), §6.2.1 (`POST /api/rooms`), §6.6 (rooms, room_settings), §8 (códigos de sala, rate limiting)
**Prioridad:** P0-Critical
**Estimación total:** XL (3–5 días)
**Dependencias:** US-006

### Criterios de Aceptación

1. `POST /api/rooms` con JWT de host válido crea una sala con `status: active`, genera un código único de 8 caracteres alfanuméricos, y retorna `201 Created` con `{ roomId, code, participantId }`.
2. La sala se crea con `owner_user_id` apuntando al `userId` del JWT.
3. Se crea automáticamente un registro en `participants` con `role: host`, `user_id` vinculado, y `status: connected`.
4. Se crea automáticamente un registro en `room_settings` con valores por defecto.
5. El código de sala se genera con `crypto.randomBytes` (8 chars alfanuméricos).
6. Rate limiting: máximo 5 salas por usuario autenticado por hora.
7. Si el código generado ya existe (colisión), se regenera automáticamente (hasta 5 reintentos).

### Tareas

#### TASK-017: Implementar RoomsModule y RoomsService

| Campo | Valor |
|-------|-------|
| **ID** | TASK-017 |
| **Tamaño** | L |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-014 |

**Especificación de implementación:**

1. Crear estructura de módulo:
   ```
   apps/api/src/rooms/
   ├── rooms.module.ts
   ├── rooms.controller.ts
   ├── rooms.controller.spec.ts
   ├── rooms.service.ts
   ├── rooms.service.spec.ts
   ├── dto/
   │   ├── create-room.dto.ts
   │   └── join-room.dto.ts
   └── utils/
       └── generate-room-code.ts
   ```

2. Implementar `generateRoomCode()`:
   ```typescript
   import { randomBytes } from 'crypto';

   export function generateRoomCode(): string {
     // Genera 6 bytes → base36 → toma los primeros 8 chars
     return randomBytes(6)
       .toString('base64url')
       .replace(/[^a-zA-Z0-9]/g, '')
       .substring(0, 8)
       .toUpperCase();
   }
   ```

3. Implementar `RoomsService`:
   - `create(userId: string | null): Promise<{ room, participant }>`:
     - Generar código con `generateRoomCode()`.
     - Intentar crear la sala con el código. Si hay colisión (P2002 en `code`), regenerar (máximo 5 reintentos).
     - Crear sala con `ownerUserId = userId`.
     - En la misma transacción Prisma, crear `RoomSettings` con defaults y `Participant` con `role: host`, `userId`, `displayName` del email del usuario (o 'Host').
     - Retornar la sala y el participante creados.
   - `findByCode(code: string): Promise<Room | null>`: Buscar sala por código de invitación incluyendo settings y participantes.
   - `findById(id: string): Promise<Room | null>`: Buscar sala por ID.
   - `findByUserId(userId: string): Promise<Room[]>`: Listar salas del usuario.
   - `isOwner(userId: string, roomId: string): Promise<boolean>`: Verificar que el usuario es el owner.

**Tests TDD (unit):**

```typescript
describe('RoomsService', () => {
  it('should create a room with unique code, settings, and host participant', async () => {
    const result = await service.create('user-uuid');
    expect(result.room.code).toHaveLength(8);
    expect(result.room.status).toBe('active');
    expect(result.room.ownerUserId).toBe('user-uuid');
    expect(result.participant.role).toBe('host');
  });

  it('should create room with null owner when userId is null', async () => {
    const result = await service.create(null);
    expect(result.room.ownerUserId).toBeNull();
  });

  it('should retry on code collision', async () => {
    // Mock Prisma para lanzar P2002 en el primer intento
    // y éxito en el segundo
    // ...
  });

  it('should find a room by its code', async () => {
    const { room } = await service.create('user-uuid');
    const found = await service.findByCode(room.code);
    expect(found).not.toBeNull();
    expect(found.id).toBe(room.id);
  });
});
```

---

#### TASK-018: Implementar endpoint POST /api/rooms y HostGuard

| Campo | Valor |
|-------|-------|
| **ID** | TASK-018 |
| **Tamaño** | L |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-017 |

**Especificación de implementación:**

1. Implementar `HostGuard` según §7.7 del TDD:
   ```typescript
   @Injectable()
   export class HostGuard implements CanActivate {
     constructor(private roomsService: RoomsService) {}

     async canActivate(context: ExecutionContext): Promise<boolean> {
       const request = context.switchToHttp().getRequest();
       const user = request.user;

       if (!user) return false;

       // Para endpoints de creación (no hay roomId aún), verificar que es host
       if (user.type === 'host') return true;

       // Para endpoints de sala específica, verificar ownership
       const roomId = request.params?.id;
       if (roomId && user.type === 'host') {
         return this.roomsService.isOwner(user.userId, roomId);
       }

       return false;
     }
   }
   ```

2. Implementar controller:
   ```typescript
   @Controller('rooms')
   export class RoomsController {
     @Post()
     @UseGuards(OptionalJwtAuthGuard)
     @Throttle({ default: { limit: 5, ttl: 3600000 } })
     @HttpCode(HttpStatus.CREATED)
     async create(@Request() req) {
       const { room, participant } = await this.roomsService.create(req.user.userId);
       return {
         roomId: room.id,
         code: room.code,
         participantId: participant.id,
       };
     }
   }
   ```

**Tests TDD (integration):**

```typescript
describe('POST /api/rooms', () => {
  let jwt: string;

  beforeEach(async () => {
    const res = await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: 'host@test.com', password: 'securePass123' });
    jwt = res.body.jwt;
  });

  it('should create a room for authenticated host', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/rooms')
      .set('Authorization', `Bearer ${jwt}`)
      .expect(201);

    expect(res.body.roomId).toBeDefined();
    expect(res.body.code).toHaveLength(8);
    expect(res.body.participantId).toBeDefined();
  });

  it('should return 401 without JWT (auth enabled)', async () => {
    await request(app.getHttpServer())
      .post('/api/rooms')
      .expect(401);
  });

  it('should return 429 after 5 rooms in 1 hour', async () => {
    for (let i = 0; i < 5; i++) {
      await request(app.getHttpServer())
        .post('/api/rooms')
        .set('Authorization', `Bearer ${jwt}`)
        .expect(201);
    }

    await request(app.getHttpServer())
      .post('/api/rooms')
      .set('Authorization', `Bearer ${jwt}`)
      .expect(429);
  });
});
```
