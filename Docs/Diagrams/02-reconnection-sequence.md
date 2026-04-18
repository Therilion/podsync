# Diagrama de Secuencia — Reconexión Durante Grabación Activa

> **Referencia TDD:** §6.4 Manejo de Desconexiones y Reconexiones, §7.7 Reconexión y Re-autenticación, §6.1.2 Buffer y Envío de Chunks

Este diagrama cubre los escenarios 1 y 2 de desconexión (breve y prolongada) durante una sesión de grabación activa, incluyendo el comportamiento del buffer local, la re-autenticación, y el restablecimiento del SFU.

```mermaid
sequenceDiagram
    autonumber

    actor User as Participante
    participant FE as Frontend (Cliente)
    participant BUF as Buffer Local<br/>(Web Worker)
    participant WS as WebSocket Gateway
    participant SFU as mediasoup SFU
    participant S3 as SeaweedFS
    participant DB as PostgreSQL

    note over FE, SFU: Grabación activa — envío normal de chunks

    FE ->> FE: MediaRecorder genera chunk N
    BUF ->> WS: chunk:data [seq=N] (binary)
    WS ->> S3: upload chunk N
    WS ->> DB: INSERT audio_chunks (seq=N)
    WS -->> BUF: chunk:ack { seq: N }
    BUF ->> BUF: Eliminar chunk N del buffer

    %% ─── DESCONEXIÓN ───
    rect rgb(239, 68, 68, 0.12)
        note over FE, WS: ⚡ Pérdida de conexión WebSocket

        WS --x FE: Conexión perdida
        FE ->> FE: Detectar cierre de WebSocket

        par Comportamiento del Cliente (offline)
            FE ->> FE: MediaRecorder SIGUE grabando
            FE ->> FE: MediaRecorder genera chunk N+1
            BUF ->> BUF: Encolar chunk N+1 (sin enviar)
            FE ->> FE: MediaRecorder genera chunk N+2
            BUF ->> BUF: Encolar chunk N+2 (sin enviar)
            note over BUF: Buffer crece hasta max 60 chunks (~5 min)
            FE ->> FE: MediaRecorder genera chunk N+3
            BUF ->> BUF: Encolar chunk N+3 (sin enviar)
        and Comportamiento del Servidor
            WS ->> WS: Heartbeat timeout (90s sin heartbeat)
            WS ->> DB: UPDATE participants SET status = 'disconnected'
            WS ->> SFU: Pausar Producer del participante
            WS -->> WS: Broadcast room:participant-left a demás clientes
        end
    end

    %% ─── RECONEXIÓN ───
    rect rgb(34, 197, 94, 0.12)
        note over FE, SFU: Reconexión con backoff exponencial

        FE ->> FE: Intento 1 (esperar 1s)
        FE --x WS: Reconexión fallida
        FE ->> FE: Intento 2 (esperar 2s)
        FE --x WS: Reconexión fallida
        FE ->> FE: Intento 3 (esperar 4s)
        FE ->> WS: Nueva conexión WebSocket exitosa

        note over FE, DB: Re-autenticación con JWT de sessionStorage

        FE ->> FE: Leer JWT de sessionStorage
        FE ->> WS: room:join { token: jwt }
        WS ->> WS: Validar JWT (Guard)
        WS ->> DB: SELECT participant WHERE id = jwt.sub AND room_id = jwt.room_id

        alt JWT válido + participant.status = 'disconnected'
            WS ->> DB: UPDATE participants SET status = 'connected'
            WS -->> WS: Broadcast room:participant-joined a demás clientes

            note over WS, SFU: Restablecer conexión SFU (mediasoup)

            WS ->> SFU: Crear nuevo WebRtcTransport (send + recv)
            WS -->> FE: transport params (id, iceParameters, dtlsParameters)
            FE ->> WS: media:transport-connect { dtlsParameters }
            FE ->> WS: media:produce { rtpParameters }
            WS ->> SFU: router.createProducer()
            WS -->> FE: producer_id
            WS ->> SFU: router.createConsumer() para otros participantes
            WS -->> FE: media:consume { producerId, rtpParameters } (×N-1)

            note over FE: Audio en vivo restaurado

            note over BUF, S3: Envío de chunks pendientes del buffer

            loop Para cada chunk pendiente en buffer (N+1, N+2, N+3...)
                BUF ->> WS: chunk:data [seq=N+K, ts_ms original] (binary)
                WS ->> WS: Validar backpressure
                WS ->> S3: upload chunk N+K
                WS ->> DB: INSERT audio_chunks (seq=N+K, ts original)
                WS -->> BUF: chunk:ack { seq: N+K }
                BUF ->> BUF: Eliminar chunk del buffer
            end

            note over BUF: Buffer vaciado — continuar envío normal

        else JWT expirado o inválido
            WS -->> FE: Error: token inválido
            FE ->> FE: Limpiar sessionStorage
            FE -->> User: "Sesión expirada. Debes unirte de nuevo."
            note over FE: Se pierde la grabación del buffer local
        end
    end
```

## Escenario 3 — Participante no regresa (grace period)

```mermaid
sequenceDiagram
    autonumber

    participant WS as WebSocket Gateway
    participant DB as PostgreSQL
    participant Q as BullMQ
    participant API as NestJS
    participant PY as Python Worker
    participant S3 as SeaweedFS

    note over WS: Host finaliza grabación mientras un participante sigue desconectado

    WS ->> DB: UPDATE recording_sessions SET status = 'grace_period'
    WS ->> WS: Iniciar timer de grace period (300,000 ms = 5 min)

    note over WS: Esperando chunks pendientes durante grace period...

    alt Chunks llegan durante grace period
        WS ->> S3: Upload chunks tardíos
        WS ->> DB: INSERT audio_chunks
    end

    WS ->> WS: Grace period expirado
    WS ->> DB: UPDATE recording_sessions SET status = 'processing'
    WS ->> DB: UPDATE audio_chunks SET status = 'irrecoverable'<br/>WHERE participant desconectado AND no recibidos
    WS ->> Q: Encolar job de procesamiento

    Q ->> API: Consumer dequeue job
    API ->> PY: POST /api/process

    PY ->> S3: Descargar chunks disponibles
    PY ->> PY: Detectar huecos en secuencia del participante ausente
    PY ->> PY: Generar silencio desde último chunk hasta fin de sesión (FFmpeg)
    PY ->> PY: Concatenar: audio real + silencio
    note over PY: La pista del participante ausente tiene la misma<br/>duración que las demás (audio parcial + silencio)
    PY ->> S3: Upload pistas procesadas
    PY ->> API: POST /internal/processing-status { completed }
```
