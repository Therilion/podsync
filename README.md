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
| Almacenamiento de objetos | MinIO (dev) / AWS S3 (prod)   |
| Base de datos             | PostgreSQL + Prisma ORM       |
| Cola de tareas            | BullMQ + Redis                |
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
   PostgreSQL        S3 / MinIO       BullMQ + Redis
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

### Puesta en marcha

```bash
# Clonar el repositorio
git clone https://github.com/Therilion/podsync.git
cd podsync

# Levantar infraestructura local
docker compose up -d

# Instalar dependencias
npm install

# Variables de entorno
cp apps/api/.env.example apps/api/.env
cp apps/web/.env.example apps/web/.env

# Inicializar base de datos
npm run db:migrate

# Iniciar en modo desarrollo
npm run dev
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
