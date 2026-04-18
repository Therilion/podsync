# Diagrama de Secuencia — Protocolo de Envío de Chunks con ACK

> **Referencia TDD:** §6.1.2 Buffer y Envío de Chunks, §6.2.3 Gestión de Chunks en S3, §6.2.4 Límites y Backpressure

Este diagrama detalla el protocolo binario de envío de chunks, el mecanismo de ACK/retry, y los edge cases de buffer overflow y backpressure.

## Flujo normal con ACK

```mermaid
sequenceDiagram
    autonumber

    participant MR as MediaRecorder
    participant BUF as Buffer Local<br/>(Web Worker)
    participant WS as WebSocket<br/>(binary frames)
    participant GW as WS Gateway<br/>(NestJS)
    participant S3 as SeaweedFS
    participant DB as PostgreSQL

    note over MR, DB: Grabación activa — timeslice: 5000ms

    MR ->> MR: ondataavailable → Blob (chunk audio)
    MR ->> BUF: Encolar chunk { seq: 0, ts_ms: 0, data: Blob }

    note over BUF: Construir frame binario (header 40B + payload)

    BUF ->> BUF: Construir header binario:<br/>session_id (16B UUID) +<br/>participant_id (16B UUID) +<br/>sequence_number (4B uint32 BE) +<br/>timestamp_ms (4B uint32 BE, relativo a recording:start)

    BUF ->> WS: Binary frame [40B header | payload WebM/Opus]
    WS ->> GW: Recibir binary message

    GW ->> GW: Parsear header: extraer session_id,<br/>participant_id, seq_num, timestamp_ms
    GW ->> GW: Validar backpressure<br/>(max 1 chunk / 3s por participante)
    GW ->> GW: Validar tamaño (max 5 MB)

    GW ->> S3: StoragePort.upload(<br/>"sessions/{sid}/participants/{pid}/chunks/{seq}.webm",<br/>payload, "audio/webm")
    S3 -->> GW: OK

    GW ->> DB: INSERT INTO audio_chunks<br/>(session_id, participant_id, seq_num,<br/>ts_start_ms, ts_end_ms, s3_key, size_bytes,<br/>status: 'received')
    DB -->> GW: OK

    GW -->> WS: chunk:ack { sequence_number: 0 }
    WS -->> BUF: ACK recibido
    BUF ->> BUF: Eliminar chunk seq=0 del buffer

    note over MR: 5 segundos después...

    MR ->> MR: ondataavailable → Blob (chunk 2)
    MR ->> BUF: Encolar chunk { seq: 1, ts_ms: 5000 }
    BUF ->> WS: Binary frame [header seq=1, ts=5000 | payload]
    note over BUF, DB: ... mismo flujo ...
```

## Flujo con retry (ACK no recibido)

```mermaid
sequenceDiagram
    autonumber

    participant BUF as Buffer Local<br/>(Web Worker)
    participant WS as WebSocket
    participant GW as WS Gateway

    BUF ->> WS: chunk:data [seq=5] (binary)
    WS ->> GW: Recibir binary message

    note over GW: Servidor procesando pero la red<br/>pierde el ACK de vuelta

    GW --x BUF: chunk:ack PERDIDO

    BUF ->> BUF: Timer de 5 segundos sin ACK para seq=5
    note over BUF: Retry #1 — backoff 5s

    BUF ->> WS: chunk:data [seq=5] (reenvío #1)
    WS ->> GW: Recibir binary message
    GW ->> GW: Detectar seq=5 duplicado (ya existe en DB)
    GW ->> GW: Ignorar upload, responder ACK (idempotente)
    GW -->> BUF: chunk:ack { sequence_number: 5 }
    BUF ->> BUF: ACK recibido — eliminar del buffer

    note over BUF: Si no hubiera recibido ACK:

    rect rgb(239, 68, 68, 0.08)
        note over BUF, GW: Retry #2 — backoff 10s
        BUF ->> WS: chunk:data [seq=5] (reenvío #2)
        GW --x BUF: chunk:ack PERDIDO

        note over BUF, GW: Retry #3 (último) — backoff 20s
        BUF ->> WS: chunk:data [seq=5] (reenvío #3)
        GW --x BUF: chunk:ack PERDIDO

        BUF ->> BUF: 3 reintentos agotados
        BUF ->> BUF: Marcar chunk como fallido (mantener en buffer)
        note over BUF: Chunk permanece en buffer para envío<br/>cuando la conexión se restablezca
    end
```

## Edge case: Buffer overflow sin conexión

```mermaid
sequenceDiagram
    autonumber

    participant MR as MediaRecorder
    participant BUF as Buffer Local<br/>(Web Worker)
    participant FE as Frontend UI

    note over MR, FE: Conexión WebSocket caída — chunks acumulándose

    loop Chunks se acumulan (sin conexión)
        MR ->> BUF: chunk seq=N
        BUF ->> BUF: buffer.length++
    end

    note over BUF: buffer.length alcanza 60 (límite = ~5 min de audio)

    MR ->> BUF: chunk seq=N+60
    BUF ->> BUF: buffer.length > 60

    alt Estrategia: rechazar nuevos (proteger los más antiguos)
        BUF ->> BUF: Descartar chunk más reciente
        BUF ->> FE: Evento: buffer_overflow
        FE ->> FE: Mostrar warning al usuario:<br/>"Conexión perdida. Algunos segmentos<br/>podrían no guardarse."
    end

    note over BUF: MediaRecorder SIGUE grabando<br/>(no se detiene para no perder el flujo del SFU)
```
