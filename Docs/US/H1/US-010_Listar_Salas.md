# US-010 — Listado e Información de Salas

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** host autenticado,
> **quiero** ver un listado de mis salas creadas y su información,
> **para** gestionar mis sesiones de grabación.

**Referencia TDD:** §6.2.1 (`GET /api/rooms`, `GET /api/rooms/:id/settings`)
**Prioridad:** P1-High
**Estimación total:** M (4–8h)
**Dependencias:** US-008

### Criterios de Aceptación

1. `GET /api/rooms` con JWT de host retorna lista de salas del usuario con id, code, status, createdAt, y número de participantes.
2. Solo retorna salas donde `owner_user_id` coincide con el JWT.
3. `GET /api/rooms/:id/settings` con JWT de host retorna la configuración de la sala (requiere ownership).
4. Un guest no puede listar salas ni ver settings.

### Tareas

#### TASK-020: Implementar endpoints de listado de salas y settings

| Campo | Valor |
|-------|-------|
| **ID** | TASK-020 |
| **Tamaño** | M |
| **Prioridad** | P1-High |
| **Dependencias** | TASK-018 |

**Especificación de implementación:**

1. Implementar en `RoomsController`:
   ```typescript
   @Get()
   @UseGuards(JwtAuthGuard)
   async listMyRooms(@Request() req) {
     if (req.user.type !== 'host') throw new ForbiddenException();
     const rooms = await this.roomsService.findByUserId(req.user.userId);
     return rooms.map(room => ({
       id: room.id,
       code: room.code,
       status: room.status,
       createdAt: room.createdAt,
       participantCount: room.participants.filter(p => p.status !== 'left').length,
     }));
   }

   @Get(':id/settings')
   @UseGuards(JwtAuthGuard, HostGuard)
   async getSettings(@Param('id') id: string) {
     const settings = await this.roomsService.getSettings(id);
     if (!settings) throw new NotFoundException();
     return settings;
   }
   ```

2. Implementar `RoomsService.getSettings(roomId: string)`.

**Tests TDD (integration):**

```typescript
describe('GET /api/rooms (list)', () => {
  it('should return rooms owned by the host', async () => {
    await request(app.getHttpServer())
      .post('/api/rooms')
      .set('Authorization', `Bearer ${hostJwt}`);

    const res = await request(app.getHttpServer())
      .get('/api/rooms')
      .set('Authorization', `Bearer ${hostJwt}`)
      .expect(200);

    expect(res.body).toHaveLength(1);
    expect(res.body[0].code).toBeDefined();
  });

  it('should not include rooms from other hosts', async () => {
    // Crear sala con otro host
    // Listar con primer host → no incluye la sala del otro
  });
});
```
