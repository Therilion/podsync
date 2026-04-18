# Diagramas de Estado — Room, Participant, Recording Session (v2)

> **Referencia TDD:** §6.6 Modelo de Datos
> **Actualizado por:** ADR-001 (Múltiples sesiones por sala y límites de tiempo configurables)
>
> **Cambios respecto a v1:**
> - `rooms.status` simplificado de 4 estados (`waiting/recording/processing/closed`) a 2 (`active/closed`)
> - Transiciones de `recording_sessions` sin cambios funcionales, pero con nuevos triggers de forzado por room TTL y recording limit
> - `participants.status` sin cambios, pero con nuevo trigger de cierre forzado por room TTL
> - Nuevos eventos WebSocket de advertencia de tiempo

---

## 1. Estados de una Sala (`rooms.status`)

```mermaid
stateDiagram-v2
    [*] --> active : POST /api/rooms<br/>(host crea sala + JWT emitido)

    active --> active : Sesiones de grabación se<br/>inician y finalizan dentro<br/>de la sala activa

    active --> closed : Host cierra sala explícitamente
    active --> closed : Room TTL expirado<br/>(max_room_duration_ms)<br/>[tras completar grace period<br/>si había grabación activa]

    closed --> [*]

    note right of active
        Participantes pueden unirse/salir.
        SFU activo para comunicación en vivo.
        Múltiples recording_sessions permitidas (secuenciales).
        Solo 1 sesión activa (recording/grace_period) a la vez.
        Sesiones anteriores pueden estar en processing/completed/failed.
        Timer de room TTL corriendo (BullMQ delayed job).
    end note

    note right of closed
        Estado terminal.
        Pistas procesadas disponibles para descarga (presigned URLs, 72h).
        Chunks crudos retenidos según política de retención.
        No se pueden iniciar nuevas grabaciones.
        Participantes desconectados.
    end note
```

### Ciclo de vida detallado de una sala con múltiples sesiones

```mermaid
sequenceDiagram
    autonumber

    participant H as Host
    participant R as Room (active)
    participant S1 as Session 1
    participant S2 as Session 2
    participant TTL as Room TTL Timer

    Note over R, TTL: Sala creada — TTL timer programado (ej. 2h)

    H ->> R: POST /rooms/:id/recording/start
    R ->> R: Validar: no hay sesión activa ✓
    R ->> R: Validar: TTL restante > 5 min ✓
    R ->> S1: Crear recording_session (status: recording)

    Note over S1: Grabación del episodio 1...

    H ->> R: POST /rooms/:id/recording/stop
    S1 ->> S1: recording → grace_period → processing
    Note over R: Sala sigue active, host y guests siguen conectados

    Note over R: Pausa — conversan, descansan

    H ->> R: POST /rooms/:id/recording/start
    R ->> R: Validar: S1 no está en recording ni grace_period ✓
    R ->> R: Validar: TTL restante > 5 min ✓
    R ->> S2: Crear recording_session (status: recording)

    Note over S2: Grabación del episodio 2...
    Note over S1: S1 completó processing → completed (en paralelo)

    H ->> R: POST /rooms/:id/recording/stop
    S2 ->> S2: recording → grace_period → processing

    H ->> R: Cerrar sala
    R ->> R: active → closed

    Note over R: Ambas sesiones disponibles para descarga
```

### Reglas de transición

| Transición | Condición de guarda | Acción |
|---|---|---|
| `active → active` (iniciar grabación) | No hay sesión en `recording` ni `grace_period` AND TTL restante > umbral mínimo (5 min) | Crear nueva `recording_session`, programar recording limit job |
| `active → closed` (host cierra) | Acción explícita del host | Si hay grabación activa: forzar stop → countdown → grace period → processing. Luego cerrar sala. Cancelar room TTL job |
| `active → closed` (TTL expirado) | `Date.now() - room.created_at >= max_room_duration_ms` | Mismo flujo que cierre por host. Warning emitido 5 min antes |

### Transiciones NO permitidas

| Transición | Razón |
|---|---|
| `closed → active` | Estado terminal. Para nueva actividad, crear nueva sala |
| Dos sesiones `recording` simultáneas | Restricción explícita (ADR-001 D3). Una sala solo puede tener una sesión grabando a la vez |

---

## 2. Estados de un Participante (`participants.status`)

```mermaid
stateDiagram-v2
    [*] --> connected : POST /rooms/:id/join<br/>(JWT emitido, WS conectado)

    connected --> disconnected : WebSocket cerrado<br/>(heartbeat timeout 90s<br/>o pérdida de conexión)

    disconnected --> connected : Reconexión exitosa<br/>[JWT válido + mismo participant_id<br/>+ sala status = active]

    connected --> left : room:leave voluntario<br/>o cierre de pestaña

    disconnected --> left : Sala cerrada (closed)<br/>o JWT expirado (24h)<br/>o room TTL expirado

    connected --> left : Sala cerrada (closed)<br/>o room TTL expirado

    left --> [*]

    note right of connected
        SFU activo (Producer + Consumers).
        Chunks enviándose (si hay sesión grabando).
        Heartbeat cada 30s.
        Puede participar en múltiples sesiones secuenciales.
    end note

    note right of disconnected
        Producer pausado en SFU.
        Chunks acumulándose en buffer del cliente.
        Servidor espera reconexión.
        Indicador visual para otros participantes.
        Persiste entre sesiones de grabación.
    end note

    note right of left
        Estado terminal para este participant_id.
        Transport SFU cerrado definitivamente.
        Si quiere volver: POST /rooms/:id/join (nuevo participant).
    end note
```

### Cambios respecto a v1

- Nuevo trigger `connected → left` por expiración de room TTL. Cuando el TTL expira y la sala se cierra, todos los participantes conectados pasan a `left`.
- Nuevo trigger `disconnected → left` por expiración de room TTL. Participantes desconectados cuando la sala se cierra también pasan a `left`.
- Explicitado: un participante `connected` persiste entre sesiones de grabación. No necesita re-unirse cuando el host inicia una nueva grabación.

---

## 3. Estados de una Sesión de Grabación (`recording_sessions.status`)

```mermaid
stateDiagram-v2
    [*] --> recording : POST /rooms/:id/recording/start<br/>[role = host,<br/>room.status = active,<br/>no hay otra sesión activa,<br/>TTL restante > 5 min]

    recording --> grace_period : Stop manual (host)<br/>o recording limit expirado<br/>o room TTL expirado

    grace_period --> processing : Grace period expirado<br/>(default: 300,000 ms)

    processing --> completed : Worker callback: completed<br/>+ pistas subidas a SeaweedFS

    processing --> failed : Worker callback: failed<br/>o timeout de procesamiento

    failed --> processing : Host solicita reprocesamiento<br/>[chunks crudos disponibles]

    completed --> [*]
    failed --> [*] : Host acepta fallo<br/>o sala cerrada

    note right of recording
        MediaRecorder activo en clientes.
        Chunks llegando al servidor.
        VAD registrando eventos.
        Cronómetro visible.
        Recording limit timer corriendo (BullMQ delayed job).
    end note

    note right of grace_period
        MediaRecorder detenido.
        Servidor acepta chunks tardíos.
        Timer decreciente.
        Recording limit job cancelado.
    end note

    note right of processing
        Worker Python activo.
        Sala puede seguir active (host puede iniciar nueva sesión).
        Descarga, concatena, normaliza, exporta.
    end note

    note right of completed
        Pistas en SeaweedFS.
        Presigned URLs generadas (72h).
        Notificaciones enviadas.
        Disponible para descarga aunque haya sesiones posteriores.
    end note

    note right of failed
        Logs de error disponibles.
        Chunks crudos preservados.
        Reprocesamiento posible.
    end note
```

### Triggers de forzado automático (nuevos en v2)

```mermaid
flowchart TB
    subgraph TRIGGERS["Triggers que causan recording → grace_period"]
        A["🟢 Manual<br/>Host presiona 'Finalizar'<br/>(flujo normal)"]
        B["🟡 Recording Limit<br/>max_recording_duration_ms expirado<br/>(BullMQ delayed job)"]
        C["🔴 Room TTL<br/>max_room_duration_ms expirado<br/>(BullMQ delayed job)"]
    end

    subgraph FLOW["Flujo posterior (igual para los 3)"]
        D["recording:countdown<br/>(3, 2, 1)"]
        E["recording:stop<br/>(todos los clientes)"]
        F["MediaRecorder.stop()"]
        G["Último chunk enviado"]
        H["grace_period inicia"]
    end

    subgraph EXTRA_C["Flujo adicional si trigger = Room TTL"]
        I["Tras grace_period + processing:<br/>room.status → closed"]
        J["Todos los participantes → left"]
    end

    A --> D
    B --> D
    C --> D
    D --> E --> F --> G --> H

    C --> I
    I --> J

    style A fill:#22c55e,color:#000
    style B fill:#eab308,color:#000
    style C fill:#ef4444,color:#fff
```

### Condiciones de guarda detalladas

| Transición | Condiciones | Acciones |
|---|---|---|
| `[*] → recording` | (1) `room.status = active` (2) No existe otra sesión con status `recording` o `grace_period` en la misma sala (3) `room.remaining_ttl > min_recording_threshold` (5 min) (4) `participant.role = host` | Crear `recording_session`, programar recording limit delayed job en BullMQ, emitir `recording:countdown` + `recording:start` |
| `recording → grace_period` (manual) | Host ejecuta stop | Cancelar recording limit job, emitir countdown + `recording:stop`, iniciar grace period timer |
| `recording → grace_period` (recording limit) | `Date.now() - session.started_at >= max_recording_duration_ms` | Emitir `recording:time-expired` + countdown + `recording:stop`, iniciar grace period timer |
| `recording → grace_period` (room TTL) | Room TTL job se dispara | Emitir `room:time-expired` + `recording:time-expired` + countdown + `recording:stop`, iniciar grace period timer. Programar cierre de sala tras grace period |
| `grace_period → processing` | Timer de grace period expirado | Marcar chunks faltantes como `irrecoverable`, encolar job en BullMQ, disparar HTTP al worker Python |
| `processing → completed` | Worker reporta éxito via callback | INSERT `processed_tracks`, generar presigned URLs, enviar notificaciones por email/webhook |
| `processing → failed` | Worker reporta error o timeout | Log de error, notificar al host, ofrecer reprocesamiento |
| `failed → processing` | Host solicita reprocesamiento | Re-encolar job en BullMQ, con mismo o diferente `processing_preset` |

---

## 4. Eventos WebSocket de Advertencia de Tiempo (nuevos)

```mermaid
sequenceDiagram
    autonumber

    participant SERVER as NestJS (Timer)
    participant HOST as Host (Frontend)
    participant GUESTS as Guests (Frontend)

    Note over SERVER: Recording limit: 5 min restantes

    SERVER -->> HOST: recording:time-warning { remaining_ms: 300000 }
    HOST ->> HOST: Mostrar banner: "5 minutos restantes de grabación"

    Note over SERVER: Recording limit expirado

    SERVER -->> HOST: recording:time-expired
    SERVER -->> GUESTS: recording:time-expired
    SERVER ->> SERVER: Forzar recording:stop (mismo flujo que stop manual)

    Note over SERVER: Room TTL: 5 min restantes

    SERVER -->> HOST: room:time-warning { remaining_ms: 300000 }
    SERVER -->> GUESTS: room:time-warning { remaining_ms: 300000 }
    HOST ->> HOST: Mostrar banner: "5 minutos restantes de sala"
    GUESTS ->> GUESTS: Mostrar banner: "5 minutos restantes de sala"

    Note over SERVER: Room TTL expirado

    SERVER -->> HOST: room:time-expired
    SERVER -->> GUESTS: room:time-expired
    Note over SERVER: Si hay grabación activa: forzar stop → grace period → processing → close
    Note over SERVER: Si no hay grabación: cerrar sala directamente
```
