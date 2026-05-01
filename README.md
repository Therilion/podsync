# PodSync

**Plataforma de grabación remota para podcasts con pistas de audio individuales por participante.**

PodSync resuelve el problema central del flujo tradicional (Discord + OBS): el audio mezclado en una sola pista. Cada participante graba localmente desde su micrófono y los fragmentos se envían al servidor en segundo plano, produciendo pistas independientes de alta calidad listas para edición profesional.

---

## El problema

El flujo habitual de grabación de podcasts remotos tiene limitaciones fundamentales:

- **Audio mezclado:** OBS captura la salida de Discord como un único stream, sin separación por participante.
- **Voces perdidas:** Cuando dos personas hablan al mismo tiempo, el volumen menor desaparece en la mezcla.
- **Calidad dependiente de la red:** Las fluctuaciones de conexión generan cortes y artefactos en la pista final.
- **Post-producción compleja:** Sin pistas separadas, normalizar, limpiar ruido o remezclar requiere técnicas avanzadas con resultados impredecibles.

## La solución

PodSync combina comunicación en vivo (WebRTC P2P) con grabación local independiente (MediaRecorder). La calidad del audio grabado es siempre la del micrófono del participante, sin importar cómo esté su conexión a internet.

---

## Características principales

**Grabación**
- Captura de audio individual desde el micrófono de cada participante
- Envío incremental de chunks al servidor (cada 5 segundos) con confirmación de recepción
- Reconexión automática con generación de silencio para cubrir huecos por desconexión
- Periodo de gracia post-sesión para recibir chunks pendientes

**Sesión en vivo**
- Comunicación de voz en tiempo real vía WebRTC P2P (hasta 5 participantes)
- Control del anfitrión: iniciar/finalizar grabación con cuenta regresiva sincronizada
- Prueba de sonido individual antes de comenzar
- Detección de actividad de voz (VAD) con indicador visual por participante
- Avatares animados idle/hablando según VAD
- Botones de muteo, levantar la mano, marca de tiempo y sugerir finalización

**Post-procesamiento**
- Concatenación de chunks por participante respetando timestamps
- Normalización de volumen a -16 LUFS (estándar podcasts)
- Reducción de ruido con RNNoise/arnndn (opcional)
- Mezcla final consolidada de todas las pistas
- Exportación en WAV (edición) y MP3 320kbps (revisión)
- Notificación por email con enlaces de descarga temporales (72h)
- Registro de eventos VAD como JSON para generación de video en post-producción

---

## Stack tecnológico

| Capa                      | Tecnología                    |
| ------------------------- | ----------------------------- |
| Frontend                  | React 19 + TypeScript + Vite  |
| UI                        | Tailwind CSS + shadcn/ui      |
| Backend API/WebSocket     | NestJS + Fastify adapter      |
| Procesamiento de audio    | Python + FFmpeg               |
| Comunicación en vivo      | WebRTC (PeerJS / simple-peer) |
| Señalización              | NestJS WebSocket Gateway      |
| Almacenamiento de objetos | SeaweedFS (dev) / AWS S3 (prod) |
| Base de datos             | PostgreSQL + Prisma ORM       |
| Cola de tareas            | BullMQ + Dragonfly (Redis-compatible) |
| Contenerización           | Docker + Docker Compose       |
| CI/CD                     | GitHub Actions                |

---

## Arquitectura

```
┌────────────────────────────────────────────────────────────┐
│                      CLIENTE (Browser)                     │
│  WebRTC Audio  │  MediaRecorder  │  WebSocket  │  React UI │
└───────┬────────────────┬─────────────────┬─────────────────┘
        │ P2P            │ chunks          │ signaling/events
┌───────┴────────────────┴─────────────────┴─────────────────┐
│              SERVIDOR (NestJS + Fastify adapter)           │
│  WS Gateway  │  Chunk Receiver  │  Room Manager  │  TURN   │
└───────┬────────────────┬─────────────────┬─────────────────┘
        │                │                 │
   PostgreSQL        S3 / SeaweedFS   BullMQ + Dragonfly
   (metadata)        (chunks)              │
                                    Audio Worker
                                  (Python / FFmpeg)
```

El flujo de datos sigue 6 fases: pre-sesión → inicio de grabación → grabación activa → finalización → procesamiento → notificación. Ver [docs/technical-design.md](docs/technical-design.md) para el diseño detallado.

---

## Desarrollo local

### Requisitos

- Node.js 20+
- Python 3.11+
- Docker y Docker Compose
- FFmpeg

### Infraestructura de desarrollo

PodSync provee un stack Docker Compose con todos los servicios de datos que el backend necesita en local: **PostgreSQL**, **Dragonfly** (caché Redis-compatible) y **SeaweedFS** (almacenamiento S3-compatible). Todo se controla por variables de entorno definidas en `.env.example`.

**Versiones fijadas (política: tag de major estable, nunca `latest`):**

| Servicio   | Imagen                                            |
| ---------- | ------------------------------------------------- |
| PostgreSQL | `postgres:18-alpine`                              |
| Dragonfly  | `docker.dragonflydb.io/dragonflydb/dragonfly:v1.27.1` |
| SeaweedFS  | `chrislusf/seaweedfs:4.21`                        |

**Arrancar el stack:**

```bash
# Copia y ajusta variables si lo necesitas
cp .env.example .env

# Levanta todos los servicios y espera a que estén healthy
docker compose up -d --wait
```

**Verificar cada servicio:**

```bash
# PostgreSQL
pg_isready -h localhost -p ${POSTGRES_PORT:-5432} -U ${POSTGRES_USER:-podsync}

# Dragonfly (protocolo Redis)
redis-cli -h localhost -p ${DRAGONFLY_PORT:-6379} ping
# → PONG

# SeaweedFS S3 gateway
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:${S3_PORT:-8333}/

# Listar buckets (debe incluir el bucket `podsync` creado al iniciar)
AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY \
AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY \
aws --endpoint-url "$S3_ENDPOINT" s3 ls
```

**Limpiar todo (incluye datos):**

```bash
docker compose down -v
```

**Credenciales de desarrollo:**

Las credenciales por defecto (`podsync_dev`, `podsync_dev_key`/`podsync_dev_secret`, etc.) están pensadas **únicamente para desarrollo local**. ⚠️ NO deben replicarse en entornos de staging ni producción — esos entornos usan secretos gestionados externamente (variables del runner, AWS Secrets Manager, etc.).

### Puesta en marcha de la app

```bash
# Clonar el repositorio
git clone https://github.com/Therilion/podsync.git
cd podsync

# Levantar infraestructura (ver sección anterior)
cp .env.example .env
docker compose up -d --wait

# Instalar dependencias
pnpm install

# Inicializar base de datos
pnpm run db:migrate

# Iniciar en modo desarrollo
pnpm run dev
```

La aplicación estará disponible en `http://localhost:5173` y la API en `http://localhost:3000`.

---

## Plan de desarrollo

| [x] | Hito | Descripción                                                  | Duración |
| --- | ---- | ------------------------------------------------------------ | -------- |
| []  | 1    | Infraestructura y comunicación básica (WebRTC + salas)       | 3-4 sem  |
| []  | 2    | **MVP** — Grabación local y envío de chunks                  | 4-5 sem  |
| []  | 3    | Resiliencia: reconexiones y silencio automático              | 3-4 sem  |
| []  | 4    | Interacción en sala: avatares, marcas de tiempo, UX          | 2-3 sem  |
| []  | 5    | Procesamiento avanzado: ruido, normalización, notificaciones | 3-4 sem  |
| []  | 6    | Reducción de ruido en cliente y optimización                 | 2-3 sem  |
| []  | 7    | Despliegue y lanzamiento                                     | 2 sem    |

**MVP disponible en ~2 meses.** 
---

## Documentación

- [Diseño técnico completo](docs/technical-design.md) — Arquitectura, requerimientos, flujos, modelo de datos y plan de hitos.

---

## Licencia

MIT
