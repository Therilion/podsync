# US-013 — Comunicación de Voz en Tiempo Real

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** participante en una sala,
> **quiero** escuchar a los demás participantes en tiempo real,
> **para** tener una conversación fluida durante la sesión de podcast.

**Referencia TDD:** §6.1.1 (SFU), §4.1.3, RF-02
**Prioridad:** P0-Critical
**Estimación total:** XL (3–5 días)
**Dependencias:** US-012

### Criterios de Aceptación

1. El cliente obtiene el stream del micrófono con `getUserMedia({ audio: true })`.
2. El audio del micrófono se envía al SFU via mediasoup-client Transport/Producer.
3. El cliente recibe y reproduce el audio de los demás participantes via Consumers.
4. La comunicación funciona entre 2 a 5 participantes simultáneamente.
5. La latencia de audio es < 300ms (RNF-02).
6. Al cerrar el navegador o pestaña, los recursos de mediasoup se liberan en el servidor.

### Tareas

#### TASK-024: Implementar cliente mediasoup en el frontend

| Campo | Valor |
|-------|-------|
| **ID** | TASK-024 |
| **Tamaño** | XL |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-023 |

**Especificación de implementación:**

1. Instalar dependencias en el frontend:
   ```bash
   pnpm add mediasoup-client
   ```

2. Crear servicio/hook `useMediasoup`:
   ```typescript
   // apps/web/src/hooks/useMediasoup.ts
   export function useMediasoup(wsConnection: WebSocket, roomId: string) {
     const [device, setDevice] = useState<mediasoupClient.Device | null>(null);
     const [sendTransport, setSendTransport] = useState<mediasoupClient.Transport | null>(null);
     const [recvTransport, setRecvTransport] = useState<mediasoupClient.Transport | null>(null);
     const [remoteStreams, setRemoteStreams] = useState<Map<string, MediaStream>>(new Map());

     // 1. Obtener RTP capabilities del router
     // 2. Crear Device y cargar capabilities
     // 3. Crear send y recv Transports
     // 4. Producir audio del micrófono
     // 5. Consumir audio de otros participantes
     // 6. Escuchar media:new-producer para consumir nuevos producers
     // 7. Escuchar media:producer-closed para limpiar consumers

     return { device, remoteStreams, produce, closeAll };
   }
   ```

3. Implementar la lógica paso a paso:

   **Paso 1 — Obtener capabilities:**
   ```typescript
   const { rtpCapabilities } = await wsRequest('media:get-rtp-capabilities', { roomId });
   const device = new mediasoupClient.Device();
   await device.load({ routerRtpCapabilities: rtpCapabilities });
   ```

   **Paso 2 — Crear Transports:**
   ```typescript
   const sendTransportInfo = await wsRequest('media:create-transport', { roomId, direction: 'send' });
   const sendTransport = device.createSendTransport(sendTransportInfo);

   sendTransport.on('connect', async ({ dtlsParameters }, callback) => {
     await wsRequest('media:transport-connect', { transportId: sendTransport.id, dtlsParameters });
     callback();
   });

   sendTransport.on('produce', async ({ kind, rtpParameters }, callback) => {
     const { producerId } = await wsRequest('media:produce', {
       transportId: sendTransport.id, kind, rtpParameters, roomId,
     });
     callback({ id: producerId });
   });
   ```

   **Paso 3 — Producir audio:**
   ```typescript
   const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
   const track = stream.getAudioTracks()[0];
   await sendTransport.produce({ track });
   ```

   **Paso 4 — Consumir audio de otros:**
   ```typescript
   async function consumeProducer(producerId: string, participantId: string) {
     const recvTransportInfo = await wsRequest('media:create-transport', { roomId, direction: 'recv' });
     // ... crear recv transport si no existe
     const consumerInfo = await wsRequest('media:consume', {
       roomId, producerId,
       rtpCapabilities: device.rtpCapabilities,
       transportId: recvTransport.id,
     });
     const consumer = await recvTransport.consume(consumerInfo);
     const stream = new MediaStream([consumer.track]);
     // Agregar a remoteStreams map
   }
   ```

4. Crear componente `AudioPlayer` que reproduzca cada stream remoto:
   ```typescript
   function AudioPlayer({ stream }: { stream: MediaStream }) {
     const audioRef = useRef<HTMLAudioElement>(null);
     useEffect(() => {
       if (audioRef.current) audioRef.current.srcObject = stream;
     }, [stream]);
     return <audio ref={audioRef} autoPlay />;
   }
   ```

5. Crear hook `useWebSocket` para gestionar la conexión WebSocket del frontend con reconexión básica y serialización/deserialización de mensajes.

**Tests TDD:**
- Tests unitarios para lógica de estado del hook (mocking mediasoup-client).
- Tests de integración manual (difíciles de automatizar con audio real; se documentan como test plan manual para E2E).
