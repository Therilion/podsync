# US-009 — Ingreso de Guest a Sala

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** invitado (guest),
> **quiero** unirme a una sala de podcast proporcionando mi nombre y el código de invitación, sin necesidad de registrarme,
> **para** participar rápidamente en la grabación.

**Referencia TDD:** §7.3 (Identidad del Guest), §6.2.1 (`POST /api/rooms/:id/join`), §3.3
**Prioridad:** P0-Critical
**Estimación total:** L (1–2 días)
**Dependencias:** US-008

### Criterios de Aceptación

1. `GET /api/rooms/:code` (público) retorna información básica de la sala (nombre/código, participantes actuales, estado).
2. `POST /api/rooms/:id/join` con `{ displayName, email? }` crea un participante con `role: guest`, `user_id: null`, y retorna `{ jwt, participantId }`.
3. El JWT del guest contiene `{ sub: participantId, roomId, role: "guest", displayName, type: "guest" }` con expiración de 24 horas.
4. Si la sala no existe o está `closed`, retorna `404` o `410 Gone`.
5. Si la sala ya tiene el máximo de participantes (5), retorna `403 Forbidden`.
6. El email es opcional. Si se proporciona, se valida formato.
7. `displayName` es obligatorio, máximo 100 caracteres.

### Tareas

#### TASK-019: Implementar endpoints de info y join de sala para guests

| Campo | Valor |
|-------|-------|
| **ID** | TASK-019 |
| **Tamaño** | L |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-017 |

**Especificación de implementación:**

1. Crear `JoinRoomDto`:
   ```typescript
   export class JoinRoomDto {
     @IsString()
     @MaxLength(100)
     displayName: string;

     @IsOptional()
     @IsEmail()
     email?: string;
   }
   ```

2. Implementar `RoomsService.join(roomId: string, dto: JoinRoomDto)`:
   - Buscar sala por ID con settings. Si no existe → `NotFoundException`.
   - Si `status === 'closed'` → `GoneException`.
   - Contar participantes con `status !== 'left'`. Si `>= maxParticipants` → `ForbiddenException`.
   - Crear participante con `role: guest`, `userId: null`.
   - Generar JWT efímero con payload de guest y expiración 24h.
   - Retornar `{ jwt, participantId }`.

3. Implementar endpoints en `RoomsController`:
   ```typescript
   @Get(':code')
   async findByCode(@Param('code') code: string) {
     const room = await this.roomsService.findByCode(code);
     if (!room) throw new NotFoundException('Sala no encontrada');
     if (room.status === 'closed') throw new GoneException('Sala cerrada');

     return {
       roomId: room.id,
       code: room.code,
       status: room.status,
       participants: room.participants
         .filter(p => p.status !== 'left')
         .map(p => ({
           id: p.id,
           displayName: p.displayName,
           role: p.role,
           status: p.status,
         })),
     };
   }

   @Post(':id/join')
   async join(
     @Param('id') id: string,
     @Body() dto: JoinRoomDto,
   ) {
     return this.roomsService.join(id, dto);
   }
   ```

**Tests TDD (integration):**

```typescript
describe('Guest room join', () => {
  let roomId: string;
  let roomCode: string;

  beforeEach(async () => {
    // Crear sala como host autenticado
    const res = await request(app.getHttpServer())
      .post('/api/rooms')
      .set('Authorization', `Bearer ${hostJwt}`)
      .expect(201);
    roomId = res.body.roomId;
    // Obtener code
    const roomRes = await request(app.getHttpServer()).get(`/api/rooms/${res.body.code}`);
    roomCode = roomRes.body.code;
  });

  it('GET /api/rooms/:code should return room info', async () => {
    const res = await request(app.getHttpServer())
      .get(`/api/rooms/${roomCode}`)
      .expect(200);

    expect(res.body.roomId).toBe(roomId);
    expect(res.body.participants).toHaveLength(1); // host
  });

  it('POST /api/rooms/:id/join should create guest participant', async () => {
    const res = await request(app.getHttpServer())
      .post(`/api/rooms/${roomId}/join`)
      .send({ displayName: 'Guest User', email: 'guest@test.com' })
      .expect(200);

    expect(res.body.jwt).toBeDefined();
    expect(res.body.participantId).toBeDefined();
  });

  it('should return 404 for non-existent room', async () => {
    await request(app.getHttpServer())
      .post(`/api/rooms/non-existent-uuid/join`)
      .send({ displayName: 'Guest' })
      .expect(404);
  });

  it('should return 403 when room is full (5 participants)', async () => {
    // Unir 4 guests (host ya ocupa 1 slot)
    for (let i = 0; i < 4; i++) {
      await request(app.getHttpServer())
        .post(`/api/rooms/${roomId}/join`)
        .send({ displayName: `Guest ${i}` });
    }

    // El sexto debe ser rechazado
    await request(app.getHttpServer())
      .post(`/api/rooms/${roomId}/join`)
      .send({ displayName: 'Guest overflow' })
      .expect(403);
  });

  it('should return 400 for missing displayName', async () => {
    await request(app.getHttpServer())
      .post(`/api/rooms/${roomId}/join`)
      .send({})
      .expect(400);
  });
});
```
