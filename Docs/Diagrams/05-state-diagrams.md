# Diagramas de Estado — Room, Participant, Recording Session

> **Referencia TDD:** §6.6 Modelo de Datos (enums de status), §6.4 Manejo de Desconexiones, §5.3 Flujo de Datos Principal

Estos diagramas formalizan las transiciones de estado que están implícitas en el TDD, resolviendo ambigüedades sobre transiciones válidas y condiciones de guarda.

---

## 1. Estados de una Sala (`rooms.status`)

```mermaid
stateDiagram-v2
    [*] --> waiting : POST /api/rooms<br/>(host crea la sala)

    waiting --> recording : POST /rooms/:id/recording/start<br/>[role = host]
    waiting --> closed : Host cierra sala sin grabar<br/>o sala inactiva (TTL expirado)

    recording --> processing : Grabación detenida +<br/>grace period expirado

    processing --> closed : Procesamiento completado<br/>(status recording_session = completed)
    processing --> closed : Procesamiento fallido<br/>(tras agotar reintentos)

    closed --> [*]

    note right of waiting
        Participantes pueden unirse/salir.
        Pruebas de sonido y avatares habilitados.
        SFU activo para comunicación en vivo.
    end note

    note right of recording
        MediaRecorder activo en todos los clientes.
        Chunks enviándose al servidor.
        No se pueden unir nuevos participantes.
    end note

    note right of processing
        Worker Python procesando pistas.
        No hay clientes activos.
        Sala en modo read-only.
    end note

    note right of closed
        Pistas disponibles para descarga.
        Presigned URLs activas (72h).
        Chunks crudos retenidos en SeaweedFS.
    end note
```

### Transiciones NO permitidas (explicitadas)

| Transición | Razón |
|---|---|
| `recording → waiting` | No se puede "deshacer" una grabación. Si el host quiere volver a grabar, se crea una nueva `recording_session` dentro de la misma sala (volver a `waiting` requiere que la sesión anterior complete su ciclo). |
| `processing → recording` | El procesamiento es terminal para esa sesión. Se puede iniciar una nueva sesión de grabación si la sala vuelve a `waiting` tras completar el procesamiento. |
| `closed → *` | Estado terminal. Para nueva grabación, crear nueva sala. |

> 🟡 **IMPORTANTE — Ambigüedad en el TDD:** El documento no especifica si una sala puede volver a `waiting` después de `processing → completed` para permitir múltiples sesiones de grabación en la misma sala. Esto requiere decisión explícita. El diagrama actual asume que cada sala tiene una única sesión de grabación. Si se permiten múltiples sesiones, se necesita la transición `closed → waiting` o `processing → waiting`.

---

## 2. Estados de un Participante (`participants.status`)

```mermaid
stateDiagram-v2
    [*] --> connected : POST /rooms/:id/join<br/>(JWT emitido, WS conectado)

    connected --> disconnected : WebSocket cerrado<br/>(heartbeat timeout 90s<br/>o pérdida de conexión)

    disconnected --> connected : Reconexión exitosa<br/>[JWT válido + mismo participant_id<br/>+ sala no cerrada]

    connected --> left : Cliente envía room:leave<br/>o cierra pestaña voluntariamente

    disconnected --> left : Sala cerrada mientras<br/>participante desconectado<br/>o JWT expirado (24h)

    left --> [*]

    note right of connected
        SFU activo (Producer + Consumers).
        Chunks enviándose (si grabando).
        Heartbeat cada 30s.
    end note

    note right of disconnected
        Producer pausado en SFU.
        Chunks acumulándose en buffer cliente.
        Servidor espera reconexión.
        Otros participantes ven indicador visual.
    end note

    note right of left
        Estado terminal para este participant_id.
        Transport SFU cerrado definitivamente.
        Si quiere volver: re-join como nuevo participant.
    end note
```

### Reglas de transición clave

| Regla | Detalle |
|---|---|
| `disconnected → connected` | Solo si: (1) JWT no expirado, (2) sala no está `closed`, (3) `participant_id` del JWT coincide con registro en DB. Si falla cualquier condición → el participante debe hacer re-join como nuevo guest. |
| `connected → left` vs `connected → disconnected` | `left` es intencional (el usuario cerró o salió). `disconnected` es involuntario (pérdida de red). La diferencia importa porque `disconnected` permite reconexión automática; `left` no. |
| No existe `left → connected` | Un participante que salió voluntariamente no puede regresar con el mismo `participant_id`. Debe crear uno nuevo. |

---

## 3. Estados de una Sesión de Grabación (`recording_sessions.status`)

```mermaid
stateDiagram-v2
    [*] --> recording : POST /rooms/:id/recording/start<br/>[role = host, room.status = waiting]

    recording --> grace_period : POST /rooms/:id/recording/stop<br/>[role = host]<br/>+ último chunk recibido de todos

    grace_period --> processing : Timer grace_period expirado<br/>(default: 300,000 ms = 5 min)

    processing --> completed : Worker callback:<br/>POST /internal/processing-status<br/>{ status: 'completed' }

    processing --> failed : Worker callback:<br/>POST /internal/processing-status<br/>{ status: 'failed' }<br/>o timeout de procesamiento

    failed --> processing : Host solicita reprocesamiento<br/>[chunks crudos aún disponibles]

    completed --> [*]
    failed --> [*] : Host acepta fallo<br/>o sala cerrada

    note right of recording
        MediaRecorder activo en clientes.
        Chunks llegando al servidor.
        VAD registrando eventos.
        Cronómetro visible.
    end note

    note right of grace_period
        MediaRecorder detenido en clientes.
        Servidor acepta chunks tardíos.
        Timer decreciente.
        No se inicia procesamiento hasta que expire.
    end note

    note right of processing
        Worker Python activo.
        Descarga, concatena, normaliza, exporta.
        room.status = 'processing'.
    end note

    note right of completed
        Pistas en SeaweedFS.
        Presigned URLs generadas.
        Notificaciones enviadas.
    end note

    note right of failed
        Logs de error disponibles.
        Chunks crudos preservados.
        Posibilidad de reprocesar.
    end note
```

### Detalle de condiciones de guarda

| Transición | Condición | Acción |
|---|---|---|
| `recording → grace_period` | Host ejecuta stop + countdown finaliza | Enviar `recording:stop` a todos, iniciar timer |
| `grace_period → processing` | `Date.now() - endedAt >= grace_period_ms` | Marcar chunks faltantes como `irrecoverable`, encolar job en BullMQ |
| `processing → completed` | Worker reporta éxito + pistas subidas a S3 | INSERT `processed_tracks`, generar presigned URLs, enviar notificaciones |
| `processing → failed` | Worker reporta error o no responde en timeout | Log de error, notificar al host, ofrecer reprocesamiento |
| `failed → processing` | Host invoca reprocesamiento manual | Re-encolar job en BullMQ con mismos o diferentes presets |
