# Diagramas C4 — Contenedores y Despliegue

> **Referencia TDD:** §5.1 Visión General, §5.2 Diagrama de Componentes, §15 Estimación de Costos de Infraestructura, §8 Consideraciones de Seguridad

---

## C4 Nivel 2 — Diagrama de Contenedores

Muestra los contenedores (procesos desplegables) del sistema PodSync y sus interacciones principales.

```mermaid
C4Container
    title PodSync — Diagrama de Contenedores (C4 Level 2)

    Person(host, "Host", "Anfitrión del podcast. Crea sala, controla grabación, configura procesamiento.")
    Person(guest, "Guest", "Participante invitado. Se une a la sala y graba su audio.")

    System_Boundary(podsync, "PodSync Platform") {
        Container(spa, "Frontend SPA", "React 19, TypeScript, Vite", "UI de sala, captura de audio con MediaRecorder, cliente mediasoup, VAD, Web Worker de envío de chunks")
        Container(api, "API + WebSocket Server", "NestJS, Fastify adapter, ws", "REST API, WebSocket Gateway (signaling + chunks), Auth JWT, BullMQ consumer, integración mediasoup")
        Container(sfu, "mediasoup Worker", "mediasoup (C++ workers via Node.js API)", "SFU: Router, WebRtcTransports, Producers/Consumers. Comunicación de audio en vivo. Ejecuta como proceso integrado con NestJS (IPC)")
        Container(worker, "Audio Processing Worker", "Python, FFmpeg, RNNoise", "REST API. Concatena chunks, genera silencio, normaliza (loudnorm), reduce ruido (arnndn), mezcla pistas, exporta FLAC/WAV/MP3")
        ContainerDb(db, "PostgreSQL", "Prisma ORM", "Metadatos: rooms, participants, sessions, chunks, VAD events, processed tracks")
        ContainerDb(cache, "Dragonfly", "Redis-compatible", "Backend de BullMQ. Cola de jobs de procesamiento")
        ContainerDb(s3, "SeaweedFS", "S3-compatible API", "Chunks de audio (WebM/Opus), pistas procesadas, avatares")
        Container(proxy, "Caddy", "Reverse Proxy", "Terminación SSL (Let's Encrypt), proxy a NestJS, WebSocket upgrade, servir frontend estático")
        Container(turn, "coturn", "TURN/STUN server", "NAT traversal para mediasoup WebRTC transports")
    }

    System_Ext(email, "Email Service", "Resend / SendGrid. Envío de notificaciones con enlaces de descarga")

    Rel(host, spa, "Usa", "HTTPS")
    Rel(guest, spa, "Usa", "HTTPS")
    Rel(spa, proxy, "HTTPS / WSS", "443")
    Rel(proxy, api, "HTTP / WS", "3000")
    Rel(proxy, spa, "Sirve estáticos", "build/")
    Rel(spa, sfu, "WebRTC (DTLS/SRTP)", "UDP 40000-49999")
    Rel(spa, turn, "STUN/TURN", "UDP/TCP 3478")
    Rel(api, sfu, "Node.js IPC", "mediasoup API")
    Rel(api, db, "TCP", "5432")
    Rel(api, cache, "TCP", "6379")
    Rel(api, s3, "HTTP", "8333 (S3 API)")
    Rel(api, worker, "HTTP", "POST /api/process")
    Rel(worker, api, "HTTP callback", "POST /internal/processing-status")
    Rel(worker, s3, "HTTP", "8333 (S3 API)")
    Rel(api, email, "API", "HTTPS")

    UpdateRelStyle(spa, proxy, $offsetX="-40", $offsetY="-10")
    UpdateRelStyle(api, sfu, $offsetX="-40", $offsetY="10")
```

---

## C4 Nivel 3 — Componentes del API Server (NestJS)

Detalle de los módulos internos del servidor NestJS.

```mermaid
C4Component
    title PodSync API Server — Componentes (C4 Level 3)

    Container_Boundary(nestjs, "NestJS + Fastify Adapter") {
        Component(auth, "AuthModule", "JWT Guard, JWT Service", "Genera y valida JWT. Guards para REST y WebSocket. HS256 con JWT_SECRET env var")
        Component(rooms, "RoomsModule", "RoomsService, RoomsController", "CRUD de salas, unirse a sala, gestión de room_settings, autorización por rol")
        Component(recording, "RecordingModule", "RecordingService, RecordingController", "Iniciar/detener grabación, countdown, grace period timer, processing_presets")
        Component(chunks, "ChunksModule", "ChunkReceiver, ChunkService", "Recibir chunks binarios via WS, parsear header 40B, validar backpressure, upload a S3, ACK")
        Component(signaling, "SignalingModule", "WebSocket Gateway", "Eventos de sala (join/leave), UI events (hand raise, suggest end, timestamp mark), VAD relay")
        Component(media, "MediaModule", "MediaService", "Integración mediasoup: crear Router, Transports, Producers, Consumers. Gestión de ciclo de vida SFU")
        Component(processing, "ProcessingModule", "BullMQ Consumer, ProcessingService", "Encolar jobs, dequeue, HTTP trigger al worker Python, recibir callbacks de status")
        Component(notifications, "NotificationsModule", "NotificationService", "Envío de emails con presigned URLs, webhooks")
        Component(storage, "StorageModule", "StoragePort interface, SeaweedFSAdapter", "Abstracción S3: upload, download, presignedUrl, delete, deletePrefix")
        Component(health, "HealthModule", "HealthController", "GET /health, /health/ready, /health/worker")
    }

    Rel(auth, rooms, "Guards protegen endpoints")
    Rel(auth, signaling, "Guard valida JWT en WS connect")
    Rel(rooms, auth, "Solicita generación de JWT al crear/unirse")
    Rel(recording, signaling, "Emite recording:countdown, recording:start/stop")
    Rel(recording, processing, "Encola job al expirar grace period")
    Rel(chunks, storage, "Upload chunks via StoragePort")
    Rel(chunks, signaling, "Recibe chunks binarios del WS Gateway")
    Rel(signaling, media, "Delega eventos media:* al MediaService")
    Rel(processing, storage, "Genera presigned URLs para descarga")
    Rel(processing, notifications, "Trigger notificaciones al completar")
    Rel(media, signaling, "Notifica nuevos Consumers, Producer closed")
    Rel(storage, health, "Health check verifica conectividad S3")
```

---

## Diagrama de Despliegue (Infraestructura)

Vista de distribución física de contenedores en servidores, con puertos y protocolos.

```mermaid
flowchart TB
    subgraph INTERNET["☁️ Internet"]
        USER["👤 Usuarios<br/>(Navegador)"]
    end

    subgraph VPS1["VPS Principal — 4 vCPU, 8 GB RAM"]
        direction TB
        CADDY["🔒 Caddy<br/>:443 (HTTPS/WSS)<br/>:80 (redirect)<br/>SSL auto (Let's Encrypt)"]

        subgraph DOCKER_MAIN["Docker Compose"]
            direction TB
            NEST["📦 NestJS API<br/>:3000 (HTTP + WS)<br/>+ mediasoup workers"]
            PG["🐘 PostgreSQL<br/>:5432"]
            DF["🐉 Dragonfly<br/>:6379"]
            SW["🗄️ SeaweedFS<br/>:8333 (S3 API)<br/>:9333 (master)<br/>Volume: /data/seaweedfs"]
            COTURN["🔄 coturn<br/>:3478 (STUN/TURN)<br/>UDP :49152-65535"]
        end
    end

    subgraph VPS2["VPS Worker — 2 vCPU, 4 GB RAM"]
        direction TB
        subgraph DOCKER_WORKER["Docker Compose"]
            PYTHON["🐍 Python Worker<br/>:8080 (REST API)<br/>FFmpeg + RNNoise"]
        end
    end

    subgraph EXTERNAL["Servicios Externos"]
        EMAIL["📧 Resend / SendGrid<br/>(API HTTPS)"]
    end

    USER -->|"HTTPS :443"| CADDY
    USER -->|"WSS :443"| CADDY
    USER -->|"WebRTC UDP<br/>:40000-49999"| NEST
    USER -->|"STUN/TURN<br/>:3478 + UDP range"| COTURN

    CADDY -->|"proxy_pass :3000"| NEST
    NEST -->|"TCP :5432"| PG
    NEST -->|"TCP :6379"| DF
    NEST -->|"HTTP :8333"| SW
    NEST -->|"IPC"| NEST

    NEST -->|"POST /api/process<br/>HTTP :8080"| PYTHON
    PYTHON -->|"POST /internal/processing-status<br/>HTTP :3000"| NEST
    PYTHON -->|"HTTP :8333"| SW

    NEST -->|"API HTTPS"| EMAIL

    style CADDY fill:#22c55e,color:#000
    style NEST fill:#3b82f6,color:#fff
    style PG fill:#336791,color:#fff
    style DF fill:#ef4444,color:#fff
    style SW fill:#f59e0b,color:#000
    style COTURN fill:#6b7280,color:#fff
    style PYTHON fill:#fbbf24,color:#000
```

## Puertos y protocolos (resumen)

| Servicio | Puerto(s) | Protocolo | Expuesto a Internet |
|---|---|---|---|
| Caddy | 443, 80 | HTTPS, HTTP (redirect) | ✅ |
| NestJS | 3000 | HTTP + WebSocket | ❌ (solo via Caddy) |
| mediasoup | 40000-49999 | UDP (WebRTC DTLS/SRTP) | ✅ (requiere apertura) |
| coturn | 3478, 49152-65535 | UDP/TCP (STUN/TURN) | ✅ |
| PostgreSQL | 5432 | TCP | ❌ |
| Dragonfly | 6379 | TCP | ❌ |
| SeaweedFS | 8333, 9333 | HTTP | ❌ |
| Python Worker | 8080 | HTTP | ❌ |

> 🟡 **IMPORTANTE:** mediasoup requiere que los puertos UDP 40000-49999 estén abiertos en el firewall del VPS para tráfico WebRTC directo. Esto se configura en `mediasoup.WebRtcTransport.listenIps`. coturn opera como fallback para clientes detrás de NAT restrictivo.
