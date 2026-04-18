# US-012 — Integración de mediasoup (SFU)

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** participante,
> **quiero** que el servidor SFU gestione la distribución de audio entre participantes,
> **para** tener comunicación de voz con bajo consumo de CPU en mi dispositivo.

**Referencia TDD:** §4.1.3 (mediasoup), §5.2 (mediasoup Worker), §6.1.1 (SFU), §6.2.2 (eventos media:*)
**Prioridad:** P0-Critical
**Estimación total:** XL (3–5 días)
**Dependencias:** US-011

### Criterios de Aceptación

1. mediasoup Worker se inicia al arrancar NestJS y se mantiene activo.
2. Al crear una sala, se crea un mediasoup `Router` con codecs de audio configurados (opus).
3. Al unirse un participante, se crean `WebRtcTransport` para send y receive.
4. El cliente puede crear un `Producer` (enviar audio) y recibir `Consumers` (audio de otros).
5. Los eventos `media:transport-connect`, `media:produce` y `media:consume` se manejan via WebSocket.
6. Al desconectarse un participante, sus Transports, Producers y Consumers se cierran limpiamente.
7. Se emite `media:producer-closed` cuando un Producer se cierra.
8. mediasoup usa codec Opus con configuración: `mimeType: 'audio/opus'`, `clockRate: 48000`, `channels: 2`.

### Tareas

#### TASK-022: Configurar mediasoup Worker y MediaModule

| Campo | Valor |
|-------|-------|
| **ID** | TASK-022 |
| **Tamaño** | L |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-021 |

**Especificación de implementación:**

1. Instalar mediasoup:
   ```bash
   pnpm add mediasoup
   ```
   **Nota:** mediasoup requiere compilador C++ y Python para builds nativos. Asegurar que el Dockerfile del backend los incluye.

2. Crear módulo `MediaModule`:
   ```
   apps/api/src/media/
   ├── media.module.ts
   ├── media.service.ts
   ├── media.service.spec.ts
   ├── interfaces/
   │   └── mediasoup-types.ts
   └── config/
       └── mediasoup.config.ts
   ```

3. Crear `mediasoup.config.ts`:
   ```typescript
   import { WorkerSettings, RouterOptions } from 'mediasoup/node/lib/types';

   export const workerSettings: WorkerSettings = {
     rtcMinPort: 10000,
     rtcMaxPort: 10100,
     logLevel: 'warn',
     logTags: ['info', 'ice', 'dtls', 'rtp', 'srtp', 'rtcp'],
   };

   export const routerOptions: RouterOptions = {
     mediaCodecs: [
       {
         kind: 'audio',
         mimeType: 'audio/opus',
         clockRate: 48000,
         channels: 2,
       },
     ],
   };

   export const webRtcTransportOptions = {
     listenIps: [
       {
         ip: process.env.MEDIASOUP_LISTEN_IP || '0.0.0.0',
         announcedIp: process.env.MEDIASOUP_ANNOUNCED_IP || '127.0.0.1',
       },
     ],
     enableUdp: true,
     enableTcp: true,
     preferUdp: true,
     maxIncomingBitrate: 128000, // Audio only
   };
   ```

4. Implementar `MediaService`:
   ```typescript
   @Injectable()
   export class MediaService implements OnModuleInit, OnModuleDestroy {
     private worker: mediasoup.types.Worker;
     private routers: Map<string, mediasoup.types.Router> = new Map();
     private transports: Map<string, mediasoup.types.WebRtcTransport> = new Map();
     private producers: Map<string, mediasoup.types.Producer> = new Map();
     private consumers: Map<string, mediasoup.types.Consumer> = new Map();

     async onModuleInit() {
       this.worker = await mediasoup.createWorker(workerSettings);
       this.worker.on('died', () => {
         logger.error('mediasoup Worker died, restarting...');
         setTimeout(() => this.onModuleInit(), 2000);
       });
     }

     async onModuleDestroy() {
       this.worker.close();
     }

     async createRouter(roomId: string): Promise<mediasoup.types.Router>;
     async getRouter(roomId: string): Promise<mediasoup.types.Router>;
     async createWebRtcTransport(roomId: string, participantId: string, direction: 'send' | 'recv'): Promise<TransportInfo>;
     async connectTransport(transportId: string, dtlsParameters: DtlsParameters): Promise<void>;
     async createProducer(transportId: string, rtpParameters: RtpParameters): Promise<ProducerInfo>;
     async createConsumer(roomId: string, producerId: string, rtpCapabilities: RtpCapabilities, transportId: string): Promise<ConsumerInfo>;
     async closeParticipantMedia(roomId: string, participantId: string): Promise<void>;
     async closeRouter(roomId: string): Promise<void>;
   }
   ```

**Tests TDD (unit):**

```typescript
describe('MediaService', () => {
  it('should create a mediasoup worker on init', async () => {
    await service.onModuleInit();
    expect(service['worker']).toBeDefined();
  });

  it('should create a router for a room', async () => {
    const router = await service.createRouter('room-1');
    expect(router).toBeDefined();
    expect(router.id).toBeDefined();
  });

  it('should create send and receive transports', async () => {
    await service.createRouter('room-1');
    const transport = await service.createWebRtcTransport('room-1', 'p-1', 'send');
    expect(transport.id).toBeDefined();
    expect(transport.iceParameters).toBeDefined();
    expect(transport.dtlsParameters).toBeDefined();
  });
});
```

---

#### TASK-023: Implementar flujo de señalización mediasoup en el Gateway

| Campo | Valor |
|-------|-------|
| **ID** | TASK-023 |
| **Tamaño** | L |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-022 |

**Especificación de implementación:**

1. Agregar handlers al `SignalingGateway` para los eventos de mediasoup:

   ```typescript
   @SubscribeMessage('media:get-rtp-capabilities')
   async handleGetRtpCapabilities(@ConnectedSocket() client, @MessageBody() data) {
     const router = await this.mediaService.getRouter(data.roomId);
     return { rtpCapabilities: router.rtpCapabilities };
   }

   @SubscribeMessage('media:create-transport')
   async handleCreateTransport(@ConnectedSocket() client, @MessageBody() data) {
     // data: { roomId, direction: 'send' | 'recv' }
     const transport = await this.mediaService.createWebRtcTransport(
       data.roomId, getParticipantId(client), data.direction,
     );
     return transport; // { id, iceParameters, iceCandidates, dtlsParameters }
   }

   @SubscribeMessage('media:transport-connect')
   async handleTransportConnect(@ConnectedSocket() client, @MessageBody() data) {
     // data: { transportId, dtlsParameters }
     await this.mediaService.connectTransport(data.transportId, data.dtlsParameters);
   }

   @SubscribeMessage('media:produce')
   async handleProduce(@ConnectedSocket() client, @MessageBody() data) {
     // data: { transportId, kind: 'audio', rtpParameters }
     const producer = await this.mediaService.createProducer(
       data.transportId, data.rtpParameters,
     );
     // Notificar a los demás participantes que hay un nuevo Producer
     this.roomConnections.broadcastToRoom(
       data.roomId, 'media:new-producer',
       { producerId: producer.id, participantId: getParticipantId(client) },
       getParticipantId(client),
     );
     return { producerId: producer.id };
   }

   @SubscribeMessage('media:consume')
   async handleConsume(@ConnectedSocket() client, @MessageBody() data) {
     // data: { roomId, producerId, rtpCapabilities, transportId }
     const consumer = await this.mediaService.createConsumer(
       data.roomId, data.producerId, data.rtpCapabilities, data.transportId,
     );
     return consumer; // { id, producerId, kind, rtpParameters }
   }
   ```

2. En `handleDisconnect`, cerrar todos los recursos mediasoup del participante:
   ```typescript
   await this.mediaService.closeParticipantMedia(roomId, participantId);
   // Emitir media:producer-closed a los demás
   ```

**Tests TDD:**

Los tests de señalización de mediasoup requieren mocks del Worker de mediasoup o integración real. Se recomienda:
- **Unit tests:** Mockear `MediaService` y verificar que el gateway llama a los métodos correctos con los parámetros correctos.
- **Integration tests:** Usar un mediasoup Worker real y verificar el flujo completo (crear router → transport → produce → consume).

```typescript
describe('SignalingGateway - mediasoup events', () => {
  it('should return router RTP capabilities on media:get-rtp-capabilities', async () => {
    // ...
  });

  it('should create send transport on media:create-transport', async () => {
    // ...
  });

  it('should broadcast new-producer to other participants on media:produce', async () => {
    // ...
  });
});
```
