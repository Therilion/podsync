# US-011 — WebSocket Gateway con Autenticación

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** participante (host o guest),
> **quiero** conectarme al WebSocket de la sala con mi JWT,
> **para** recibir eventos en tiempo real (participantes entrando/saliendo, señalización).

**Referencia TDD:** §6.2.2 (Eventos WebSocket), §7.5 (Uso del Token), §5.2
**Prioridad:** P0-Critical
**Estimación total:** XL (3–5 días)
**Dependencias:** US-009

### Criterios de Aceptación

1. El WebSocket Gateway acepta conexiones en el namespace `/ws` (o path configurado).
2. El evento `room:join` requiere un campo `token` con un JWT válido (host o guest).
3. Si el JWT es inválido o expirado, el servidor cierra la conexión con error.
4. El evento `room:participant-joined` se emite a todos los participantes existentes cuando alguien nuevo se une.
5. El evento `room:participant-left` se emite a todos cuando alguien desconecta.
6. El servidor trackea las conexiones activas por sala (map `roomId → Set<socketId>`).
7. El heartbeat WebSocket funciona con interval de 30 segundos y timeout de 90 segundos.

### Tareas

#### TASK-021: Implementar WebSocket Gateway base con autenticación JWT

| Campo | Valor |
|-------|-------|
| **ID** | TASK-021 |
| **Tamaño** | XL |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-019 |

**Especificación de implementación:**

1. Instalar dependencias:
   ```bash
   pnpm add @nestjs/websockets @nestjs/platform-ws ws
   pnpm add -D @types/ws
   ```

2. Crear módulo `SignalingModule`:
   ```
   apps/api/src/signaling/
   ├── signaling.module.ts
   ├── signaling.gateway.ts
   ├── signaling.gateway.spec.ts
   ├── guards/
   │   └── ws-auth.guard.ts
   └── services/
       └── room-connections.service.ts
   ```

3. Implementar `RoomConnectionsService`:
   ```typescript
   @Injectable()
   export class RoomConnectionsService {
     // roomId → Map<participantId, WebSocket>
     private rooms = new Map<string, Map<string, WebSocket>>();

     addConnection(roomId: string, participantId: string, socket: WebSocket): void;
     removeConnection(roomId: string, participantId: string): void;
     getParticipantsInRoom(roomId: string): string[];
     broadcastToRoom(roomId: string, event: string, data: any, exclude?: string): void;
     getSocket(roomId: string, participantId: string): WebSocket | undefined;
   }
   ```

4. Implementar `SignalingGateway`:
   ```typescript
   @WebSocketGateway({ path: '/ws' })
   export class SignalingGateway implements OnGatewayConnection, OnGatewayDisconnect {

     handleConnection(client: WebSocket): void {
       // Iniciar timeout de autenticación: si no envía room:join en 10s, desconectar
     }

     handleDisconnect(client: WebSocket): void {
       // Remover de RoomConnectionsService
       // Emitir room:participant-left a los demás
       // Actualizar participant.status = 'disconnected' en DB
     }

     @SubscribeMessage('room:join')
     async handleRoomJoin(
       @ConnectedSocket() client: WebSocket,
       @MessageBody() data: { token: string },
     ) {
       // 1. Verificar JWT (JwtService.verify)
       // 2. Extraer roomId y participantId del payload
       // 3. Verificar que la sala existe y está activa
       // 4. Verificar que el participante pertenece a la sala
       // 5. Registrar en RoomConnectionsService
       // 6. Actualizar participant.status = 'connected'
       // 7. Emitir room:participant-joined a los demás
       // 8. Responder con lista de participantes actuales
     }

     @SubscribeMessage('room:leave')
     async handleRoomLeave(@ConnectedSocket() client: WebSocket) {
       // Actualizar participant.status = 'left'
       // Emitir room:participant-left
       // Cerrar conexión
     }
   }
   ```

5. Configurar heartbeat en el WebSocket adapter:
   ```typescript
   // En main.ts o en la configuración del adapter
   const wss = new WebSocketServer({
     server,
     path: '/ws',
   });

   // Heartbeat interval
   const interval = setInterval(() => {
     wss.clients.forEach((ws) => {
       if (ws.isAlive === false) return ws.terminate();
       ws.isAlive = false;
       ws.ping();
     });
   }, 30000);

   wss.on('connection', (ws) => {
     ws.isAlive = true;
     ws.on('pong', () => { ws.isAlive = true; });
   });
   ```

**Tests TDD (integration):**

```typescript
describe('SignalingGateway', () => {
  it('should accept connection with valid JWT on room:join', async () => {
    const ws = new WebSocket(`ws://localhost:${port}/ws`);
    await waitForOpen(ws);

    ws.send(JSON.stringify({
      event: 'room:join',
      data: { token: guestJwt },
    }));

    const response = await waitForMessage(ws);
    expect(response.event).toBe('room:join');
    expect(response.data.participants).toBeDefined();
  });

  it('should reject connection with invalid JWT', async () => {
    const ws = new WebSocket(`ws://localhost:${port}/ws`);
    await waitForOpen(ws);

    ws.send(JSON.stringify({
      event: 'room:join',
      data: { token: 'invalid-jwt' },
    }));

    const response = await waitForMessage(ws);
    expect(response.event).toBe('error');
  });

  it('should notify others when participant joins', async () => {
    // Host conectado
    const hostWs = await connectAndJoin(hostJwt);

    // Guest se une
    const guestWs = await connectAndJoin(guestJwt);

    // Host debería recibir room:participant-joined
    const msg = await waitForMessage(hostWs);
    expect(msg.event).toBe('room:participant-joined');
  });

  it('should notify others when participant disconnects', async () => {
    const hostWs = await connectAndJoin(hostJwt);
    const guestWs = await connectAndJoin(guestJwt);

    guestWs.close();

    const msg = await waitForMessage(hostWs);
    expect(msg.event).toBe('room:participant-left');
  });
});
```
