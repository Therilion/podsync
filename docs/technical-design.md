# PodSync

**Plataforma de Grabación Remota para Podcasts**

Documento Técnico de Diseño — Versión 1.3 — Abril 2026

**CONFIDENCIAL**

---

## Índice de Contenido

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Problemática Actual](#2-problemática-actual)
3. [Análisis de Requerimientos](#3-análisis-de-requerimientos)
4. [Selección del Stack Tecnológico](#4-selección-del-stack-tecnológico)
5. [Arquitectura del Sistema](#5-arquitectura-del-sistema)
6. [Diseño Detallado de Componentes](#6-diseño-detallado-de-componentes)
7. [Consideraciones de Seguridad](#7-consideraciones-de-seguridad)
8. [Plan de Desarrollo por Hitos](#8-plan-de-desarrollo-por-hitos)
9. [Matriz de Trazabilidad: Requerimientos vs Hitos](#9-matriz-de-trazabilidad-requerimientos-vs-hitos)
10. [Iteraciones Futuras (Post-Lanzamiento)](#10-iteraciones-futuras-post-lanzamiento)
11. [Resumen del Timeline](#11-resumen-del-timeline)
12. [Estimación de Costos de Infraestructura](#12-estimación-de-costos-de-infraestructura)
13. [Conclusiones](#13-conclusiones)

---

## 1. Resumen Ejecutivo

PodSync es una plataforma web diseñada para la grabación remota de podcasts con captura de audio individual por participante. A diferencia del flujo actual basado en Discord + OBS, donde el audio se mezcla en una sola pista, PodSync permite que cada participante grabe localmente en su dispositivo y envíe fragmentos al servidor en segundo plano, resultando en pistas de audio independientes y de alta calidad que facilitan la edición y post-producción.

Este documento detalla la arquitectura, el stack tecnológico, los flujos de datos, y el plan de desarrollo incremental organizado en hitos para llevar el producto desde su MVP hasta una solución completa.

---

## 2. Problemática Actual

### 2.1 Descripción del Problema

El flujo actual de grabación presenta las siguientes deficiencias:

- **Audio mezclado en una sola pista:** OBS captura la salida de audio de Discord como un único stream, mezclando todas las voces. Esto imposibilita la normalización individual del volumen.
- **Pérdida de diálogos:** Cuando dos o más personas hablan simultáneamente, las voces con menor volumen se pierden al estar mezcladas.
- **Inestabilidad de conexión:** Las fluctuaciones de red de los participantes afectan la calidad del audio grabado, generando cortes y artefactos en la pista final.
- **Edición compleja:** Sin pistas separadas, la post-producción requiere técnicas avanzadas (noise gates, compresores laterales) que no siempre logran resultados óptimos.

### 2.2 Solución Propuesta

Desarrollar una aplicación web que permita a los participantes reunirse en una sala virtual donde se puedan comunicar en tiempo real mediante WebRTC, mientras que en paralelo cada cliente graba su propio audio localmente usando la MediaRecorder API del navegador. Estos fragmentos de audio se envían de forma incremental al servidor vía WebSocket, que a su vez los almacena en un servicio compatible con S3. Al finalizar la sesión, se procesan las pistas individuales y se genera también una mezcla consolidada.

---

## 3. Análisis de Requerimientos

### 3.1 Requerimientos Funcionales

| ID    | Requerimiento                                                               | Prioridad |
| ----- | --------------------------------------------------------------------------- | --------- |
| RF-01 | Crear sala de podcast con código/enlace de invitación                       | Alta      |
| RF-02 | Comunicación de voz en tiempo real entre participantes (hasta 5)            | Alta      |
| RF-03 | Grabación local de audio individual en cada dispositivo                     | Alta      |
| RF-04 | Envío de fragmentos de audio (chunks) al servidor en segundo plano          | Alta      |
| RF-05 | Almacenamiento de chunks en servicio compatible con S3                      | Alta      |
| RF-06 | Control del anfitrión: iniciar/finalizar grabación con cuenta regresiva     | Alta      |
| RF-07 | Prueba de sonido individual antes de iniciar grabación (escuchar/descargar) | Alta      |
| RF-08 | Botón de muteo/desmuteo de micrófono                                        | Alta      |
| RF-09 | Botón de levantar la mano (aviso visual a todos)                            | Media     |
| RF-10 | Botón de marca de tiempo (timestamp bookmark)                               | Media     |
| RF-11 | Botón de sugerencia de finalización de sesión                               | Media     |
| RF-12 | Reconexión automática con generación de silencio en pista del ausente       | Alta      |
| RF-13 | Generación de pista final con mezcla de todos los participantes             | Alta      |
| RF-14 | Notificación a posteriori con enlace de descarga cuando audios estén listos | Media     |
| RF-15 | Periodo de gracia post-sesión para recibir chunks pendientes                | Alta      |
| RF-16 | Reducción de ruido opcional en el audio capturado                           | Baja      |
| RF-17 | Detección de actividad de voz (VAD) con indicador visual por participante   | Media     |
| RF-18 | Avatares animados: subir imagen idle/hablando con alternancia por VAD       | Media     |
| RF-19 | Registro de eventos VAD (timestamps inicio/fin de voz) para post-producción | Media     |

### 3.2 Requerimientos No Funcionales

| ID     | Requerimiento                           | Métrica                               |
| ------ | --------------------------------------- | ------------------------------------- |
| RNF-01 | Bajo consumo de recursos en el cliente  | < 10% CPU, < 150 MB RAM               |
| RNF-02 | Latencia de comunicación en tiempo real | < 300 ms (audio conversacional)       |
| RNF-03 | Tolerancia a pérdida de paquetes        | Recuperación sin pérdida de grabación |
| RNF-04 | Disponibilidad del servicio             | > 99.5% uptime                        |
| RNF-05 | Compatibilidad de navegadores           | Chrome, Firefox, Edge, Safari         |
| RNF-06 | Tiempo de procesamiento post-sesión     | < 2x la duración del episodio         |
| RNF-07 | Escalabilidad                           | Múltiples salas concurrentes          |

### 3.3 Restricciones

- Máximo 5 participantes por sala.
- Plataforma web (navegador) como target principal del MVP.
- Sin sistema de cuentas en el MVP; acceso por enlace de invitación.
- El audio procesado no estará disponible para descarga inmediata.

---

## 4. Selección del Stack Tecnológico

### 4.1 Análisis Comparativo

Se analizaron las opciones vigentes para cada componente del sistema, priorizando eficiencia, ecosistema, y bajo consumo de recursos.

#### 4.1.1 Frontend

| Opción             | Ventajas                                                                           | Desventajas                                      | Veredicto          |
| ------------------ | ---------------------------------------------------------------------------------- | ------------------------------------------------ | ------------------ |
| React + TypeScript | Ecosistema maduro, amplia comunidad, excelente soporte para WebRTC y Web Audio API | Bundle size mayor que alternativas más ligeras   | **SELECCIONADO**   |
| SvelteKit          | Bundle más pequeño, reactivo por defecto                                           | Ecosistema más pequeño para integraciones WebRTC | Alternativa viable |
| Vue 3              | API de composición moderna, buen rendimiento                                       | Menos librerías específicas para audio/WebRTC    | Descartado         |

#### 4.1.2 Backend

| Opción                   | Ventajas                                                                                                 | Desventajas                                                        | Veredicto                                                          |
| ------------------------ | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| NestJS (Fastify adapter) | Arquitectura modular, inyección de dependencias, WebSocket Gateways nativos, mismo lenguaje que frontend | Mayor consumo de memoria base (~30-60 MB extra vs Fastify puro)    | **SELECCIONADO**                                                   |
| Node.js (Fastify puro)   | Mínimo overhead, alto throughput, bajo consumo de memoria                                                | Sin estructura opinada, requiere más código de organización manual | Evaluado, descartado por menor mantenibilidad                      |
| Go                       | Alto rendimiento, concurrencia nativa con goroutines, bajo consumo de memoria                            | Lenguaje diferente al frontend, curva de aprendizaje               | Alternativa para escalar servicios auxiliares de alta concurrencia |
| Python (FastAPI)         | Excelente para procesamiento de audio (scipy, librosa)                                                   | Mayor consumo de memoria, GIL limita concurrencia                  | **SELECCIONADO** para servicio de procesamiento de audio           |

#### 4.1.3 Comunicación en Tiempo Real

| Opción                | Ventajas                                                  | Desventajas                                    | Veredicto                               |
| --------------------- | --------------------------------------------------------- | ---------------------------------------------- | --------------------------------------- |
| WebRTC (peer-to-peer) | Baja latencia, sin pasar por servidor, cifrado E2E        | Complejidad de NAT traversal, calidad variable | **SELECCIONADO** para audio en vivo     |
| mediasoup (SFU)       | Menor carga en clientes, mejor control del servidor       | Mayor complejidad de infraestructura           | Alternativa para escalar a > 5 personas |
| LiveKit               | SFU open-source completo, SDKs para múltiples plataformas | Requiere servidor dedicado                     | Evaluado para iteraciones futuras       |

#### 4.1.4 Almacenamiento

| Opción                  | Ventajas                                                         | Desventajas                                            | Veredicto                              |
| ----------------------- | ---------------------------------------------------------------- | ------------------------------------------------------ | -------------------------------------- |
| SeaweedFS (self-hosted) | Compatible con S3 API, licencia Apache 2.0, ligero, bajo consumo | Comunidad más pequeña, menos documentación empresarial | **SELECCIONADO** para MVP / desarrollo |
| AWS S3                  | Alta disponibilidad, escalabilidad automática                    | Costos variables por almacenamiento y transferencia    | **SELECCIONADO** para producción       |
| Cloudflare R2           | Compatible S3, sin costos de egress                              | Menor ecosistema de herramientas                       | Alternativa viable en costos           |

### 4.2 Stack Seleccionado (Resumen)

| Componente              | Tecnología                                    | Justificación                                                |
| ----------------------- | --------------------------------------------- | ------------------------------------------------------------ |
| Frontend                | React 19 + TypeScript + Vite                  | Madurez del ecosistema, excelente soporte Web APIs           |
| UI Framework            | Tailwind CSS + shadcn/ui                      | Desarrollo rápido, consistencia visual, bajo overhead        |
| Backend (API/WebSocket) | NestJS + Fastify adapter + @nestjs/websockets | Arquitectura modular, DI, WebSocket Gateways, mismo lenguaje |
| Backend (Procesamiento) | Python + FFmpeg                               | Ecosistema líder en procesamiento de audio                   |
| Comunicación en vivo    | WebRTC (PeerJS / simple-peer)                 | P2P nativo del navegador, baja latencia                      |
| Señalización            | NestJS WebSocket Gateway (ws)                 | Integrado con el framework, decoradores tipados              |
| Almacenamiento objetos  | SeaweedFS (dev) / AWS S3 (prod)               | API S3-compatible, Apache 2.0, bajo consumo de recursos      |
| Base de datos           | PostgreSQL + Prisma ORM                       | Robusto, relacional, excelente con Node.js                   |
| Cola de tareas          | BullMQ + Dragonfly                            | Procesamiento asíncrono confiable, multi-threaded, BSL 1.1   |
| Procesamiento audio     | FFmpeg + RNNoise (WASM)                       | Estándar de la industria + reducción de ruido eficiente      |
| Contenerización         | Docker + Docker Compose                       | Entorno reproducible, fácil despliegue                       |
| CI/CD                   | GitHub Actions                                | Integración nativa con repositorios                          |

---

## 5. Arquitectura del Sistema

### 5.1 Visión General

La arquitectura se organiza en capas claramente separadas siguiendo un patrón de microservicios ligeros, donde cada componente tiene una responsabilidad bien definida:

1. **Capa de Cliente (Browser):** Captura de audio local, grabación con MediaRecorder, envío de chunks, comunicación WebRTC.
2. **Capa de Señalización y API (NestJS):** Gestión de salas, WebSocket Gateways para signaling, recepción de chunks, coordinación de grabación. Organizado en módulos: RoomsModule, RecordingModule, SignalingModule, ChunksModule.
3. **Capa de Almacenamiento:** S3-compatible para chunks de audio, PostgreSQL para metadatos de sesiones.
4. **Capa de Procesamiento (Worker):** Concatenación de chunks, generación de silencio, reducción de ruido, mezcla final.
5. **Capa de Notificación:** Aviso por email/webhook cuando los audios están listos para descarga.

### 5.2 Diagrama de Componentes

```
┌────────────────────────────────────────────────────────────────────────────┐
│                            CLIENTE (Browser)                               │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐   │
│  │ WebRTC Audio  │ │ MediaRecorder │ │  WebSocket    │ │   React UI    │   │
│  │ (live comms)  │ │ (local rec)   │ │ (signaling)   │ │  (interface)  │   │
│  └───────┬───────┘ └───────┬───────┘ └───────┬───────┘ └───────────────┘   │
└──────────┼─────────────────┼─────────────────┼─────────────────────────────┘
           │                 │ (chunks)        │ (signaling + events)
           │ P2P             │                 │
┌──────────┴─────────────────┴─────────────────┴────────────────────────────┐
│                    SERVIDOR (NestJS + Fastify adapter)                    │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐  │
│  │  WS Gateway   │ │Chunk Receiver │ │ Room Manager  │ │   STUN/TURN   │  │
│  └───────┬───────┘ └───────┬───────┘ └───────┬───────┘ └───────────────┘  │
└──────────┼─────────────────┼─────────────────┼────────────────────────────┘
           │                 │                 │
     ┌─────┴──────┐    ┌─────┴───────┐   ┌─────┴─────┐
     │ PostgreSQL │    │  SeaweedFS  │   │ BullMQ +  │
     │ (metadata) │    │  (chunks)   │   │ Dragonfly │
     └────────────┘    └─────────────┘   └─────┬─────┘
                                               │
                                     ┌─────────┴─────────┐
                                     │   Audio Worker    │
                                     │ (Python / FFmpeg) │
                                     └───────────────────┘
```

### 5.3 Flujo de Datos Principal

El flujo de datos durante una sesión de grabación sigue estas fases:

**Fase 1 — Pre-sesión:** El anfitrión crea la sala y obtiene un enlace de invitación. Los participantes se unen, establecen conexiones WebRTC peer-to-peer para comunicación en vivo, y realizan pruebas de sonido.

**Fase 2 — Inicio de grabación:** El anfitrión presiona el botón de iniciar grabación. Se emite un evento por WebSocket a todos los clientes mostrando una cuenta regresiva sincronizada (3, 2, 1). Al llegar a cero, cada cliente inicia su MediaRecorder local.

**Fase 3 — Grabación activa:** Cada cliente genera chunks de audio cada 5 segundos (configurable). Los chunks se encolan localmente en un buffer y se envían al servidor vía WebSocket binary frames. El servidor los recibe, les asigna metadatos (timestamp, participante, número de secuencia) y los sube a S3.

**Fase 4 — Finalización:** El anfitrión presiona finalizar, se emite cuenta regresiva de cierre, y al llegar a cero cada cliente envía su último chunk con flag de finalización. El servidor espera un periodo de gracia (configurable, 30-60 segundos por defecto) para recibir chunks pendientes de participantes con conexión inestable.

**Fase 5 — Procesamiento:** Un worker toma los chunks de S3, los concatena por participante respetando timestamps, genera silencio donde haya huecos por desconexión, aplica reducción de ruido opcional, y produce la pista individual y la mezcla final.

**Fase 6 — Notificación:** Una vez procesados los audios, se notifica a los participantes (vía email o webhook) con el enlace de descarga temporal.

---

## 6. Diseño Detallado de Componentes

### 6.1 Cliente (Frontend)

#### 6.1.1 Captura de Audio Local

Se utilizará la API `navigator.mediaDevices.getUserMedia()` para obtener el stream del micrófono del usuario. Este stream alimenta dos flujos paralelos:

- **WebRTC:** El stream se agrega a las conexiones `RTCPeerConnection` para que los demás participantes escuchen en tiempo real.
- **MediaRecorder:** El mismo stream se graba localmente usando `MediaRecorder` con codec Opus en contenedor WebM (`audio/webm;codecs=opus`). Se configura con `timeslice` de 5000ms para generar chunks periódicos.

Esta arquitectura dual garantiza que la grabación es independiente de la calidad de la conexión: incluso si WebRTC sufre packet loss, la grabación local mantiene la calidad original del micrófono.

#### 6.1.2 Buffer y Envío de Chunks

Los chunks generados por MediaRecorder se encolan en un buffer local implementado como un array en memoria. Un worker de envío (implementado como un Web Worker para no bloquear el hilo principal) toma chunks del buffer y los envía por WebSocket en formato binario. El protocolo de envío incluye:

- **Header binario de 32 bytes:** session_id (16 bytes UUID), participant_id (8 bytes), sequence_number (4 bytes), timestamp_ms (4 bytes).
- **Payload:** datos crudos del chunk WebM/Opus.
- **Acknowledgment:** el servidor responde con ACK incluyendo el sequence_number para confirmar recepción. Si no se recibe ACK en 5 segundos, el chunk se reintenta.

Si la conexión WebSocket se pierde, los chunks se acumulan en el buffer local (limitado a 50 chunks / ~4 minutos de audio) y se envían al reconectarse, garantizando que no se pierde audio.

#### 6.1.3 Interfaz de Usuario

La interfaz se organiza en los siguientes elementos principales:

| Elemento                  | Descripción                                                                                   | Disponibilidad    |
| ------------------------- | --------------------------------------------------------------------------------------------- | ----------------- |
| Panel de participantes    | Avatares personalizados con alternancia idle/hablando según VAD e indicador de nivel de audio | Siempre visible   |
| Botón Mutear/Desmutear    | Toggle del micrófono local (afecta WebRTC y grabación)                                        | Siempre visible   |
| Botón Levantar Mano       | Envía evento visual a todos los participantes                                                 | Siempre visible   |
| Botón Marca de Tiempo     | Crea bookmark con timestamp actual para referencia en edición                                 | Durante grabación |
| Botón Sugerir Fin         | Envía notificación al anfitrión sugiriendo cerrar la sesión                                   | Durante grabación |
| Botón Prueba de Sonido    | Graba 10 segundos y permite reproducir/descargar                                              | Pre-grabación     |
| Subida de Avatar          | Formulario para subir imagen idle y hablando (PNG/GIF, max 2 MB c/u)                          | Pre-grabación     |
| Botón Iniciar Grabación   | Lanza cuenta regresiva e inicia grabación (solo anfitrión)                                    | Pre-grabación     |
| Botón Finalizar Grabación | Lanza cuenta regresiva de cierre (solo anfitrión)                                             | Durante grabación |
| Indicador de Estado       | Muestra estado: conectando, en sala, grabando, procesando                                     | Siempre visible   |
| Cronómetro de Sesión      | Tiempo transcurrido desde inicio de grabación                                                 | Durante grabación |

### 6.2 Servidor (Backend)

#### 6.2.1 API REST

| Endpoint                         | Método | Descripción                                               |
| -------------------------------- | ------ | --------------------------------------------------------- |
| `/api/rooms`                     | POST   | Crear nueva sala (retorna room_id y código de invitación) |
| `/api/rooms/:code`               | GET    | Obtener info de sala por código de invitación             |
| `/api/rooms/:id/join`            | POST   | Unirse a sala (registra participante)                     |
| `/api/rooms/:id/recording/start` | POST   | Iniciar grabación (solo anfitrión)                        |
| `/api/rooms/:id/recording/stop`  | POST   | Finalizar grabación (solo anfitrión)                      |
| `/api/rooms/:id/timestamps`      | POST   | Crear marca de tiempo                                     |
| `/api/rooms/:id/timestamps`      | GET    | Listar marcas de tiempo de la sesión                      |
| `/api/sessions/:id/download`     | GET    | Obtener enlaces de descarga (post-procesamiento)          |
| `/api/sound-check`               | POST   | Subir grabación de prueba de sonido                       |

#### 6.2.2 Eventos WebSocket

| Evento                    | Dirección                  | Descripción                                                    |
| ------------------------- | -------------------------- | -------------------------------------------------------------- |
| `room:join`               | Cliente → Servidor         | Participante se une a la sala                                  |
| `room:leave`              | Cliente → Servidor         | Participante abandona la sala                                  |
| `room:participant-joined` | Servidor → Clientes        | Notifica nuevo participante                                    |
| `room:participant-left`   | Servidor → Clientes        | Notifica salida de participante                                |
| `recording:countdown`     | Servidor → Clientes        | Cuenta regresiva de inicio/fin                                 |
| `recording:start`         | Servidor → Clientes        | Orden de iniciar MediaRecorder                                 |
| `recording:stop`          | Servidor → Clientes        | Orden de detener y enviar chunks restantes                     |
| `chunk:data`              | Cliente → Servidor         | Envío de chunk de audio (binario)                              |
| `chunk:ack`               | Servidor → Cliente         | Confirmación de chunk recibido                                 |
| `signal:offer`            | Cliente → Servidor         | WebRTC SDP offer (relay)                                       |
| `signal:answer`           | Cliente → Servidor         | WebRTC SDP answer (relay)                                      |
| `signal:ice-candidate`    | Cliente → Servidor         | ICE candidate (relay)                                          |
| `ui:hand-raise`           | Cliente ↔ Todos            | Levantar/bajar la mano                                         |
| `ui:suggest-end`          | Cliente → Anfitrión        | Sugerir finalización de sesión                                 |
| `ui:timestamp-mark`       | Cliente → Servidor         | Crear marca de tiempo                                          |
| `vad:state`               | Cliente → Servidor → Todos | Cambio de estado de voz (speaking/silent) para animar avatares |

#### 6.2.3 Gestión de Chunks en S3

Los chunks se almacenan en S3 con la siguiente estructura de claves:

```
sessions/{session_id}/participants/{participant_id}/chunks/{sequence_number}.webm
```

Adicionalmente se almacenan metadatos en PostgreSQL con la tabla `audio_chunks` que registra: chunk_id, session_id, participant_id, sequence_number, timestamp_start_ms, timestamp_end_ms, s3_key, size_bytes, received_at. Esto permite reconstruir la línea temporal completa de cada participante.

### 6.3 Procesamiento de Audio (Worker)

El worker de procesamiento es un servicio Python que escucha la cola BullMQ (vía bridge) y ejecuta las siguientes tareas al finalizar una sesión:

1. **Descarga de chunks:** Descarga todos los chunks de S3 para cada participante de la sesión.
2. **Verificación de secuencia:** Ordena por sequence_number y detecta huecos (chunks faltantes por desconexión).
3. **Generación de silencio:** Para cada hueco detectado, genera un segmento de silencio con la duración correspondiente usando FFmpeg.
4. **Concatenación:** Une todos los chunks (incluyendo segmentos de silencio) en orden cronológico para producir la pista individual de cada participante.
5. **Reducción de ruido (opcional):** Aplica filtro de reducción de ruido basado en RNNoise (arnndn en FFmpeg) que utiliza redes neuronales recurrentes. Es eficiente, preserva la calidad vocal, y opera en tiempo lineal.
6. **Normalización:** Aplica loudnorm de FFmpeg para normalizar el volumen a -16 LUFS (estándar para podcasts).
7. **Mezcla final:** Combina todas las pistas individuales en una pista consolidada usando FFmpeg amix filter.
8. **Exportación:** Genera archivos finales en formato WAV (calidad máxima para edición) y MP3 320kbps (para revisión rápida). Los sube a S3 y actualiza la base de datos.
9. **Notificación:** Envía notificación con enlaces de descarga temporales (presigned URLs con expiración de 72 horas).

### 6.4 Manejo de Desconexiones y Reconexiones

Este es uno de los aspectos más críticos del sistema. El diseño contempla múltiples escenarios:

**Escenario 1 — Desconexión breve (< 30s):** El cliente detecta la caída del WebSocket e intenta reconectar automáticamente con backoff exponencial. Los chunks se acumulan en el buffer local. Al reconectar, envía todos los chunks pendientes con sus timestamps originales. El servidor los procesa normalmente.

**Escenario 2 — Desconexión prolongada (> 30s, < duración sesión):** Además del comportamiento anterior, el servidor marca al participante como "desconectado" y notifica a los demás. Si el participante vuelve, se restablece la conexión WebRTC con los peers activos. Los chunks acumulados se envían y los huecos se cubrirán con silencio en post-procesamiento.

**Escenario 3 — Participante no regresa:** Si la sesión termina y un participante no se reconectó, el servidor espera el periodo de gracia configurado (por defecto 60 segundos). Transcurrido ese tiempo, el worker genera silencio desde el último chunk recibido hasta el final de la sesión, produciendo una pista completa con la misma duración que las demás.

**Escenario 4 — Pérdida total del dispositivo:** En el peor caso, si el cliente pierde el dispositivo y no puede enviar chunks pendientes, la pista del participante contendrá audio hasta el último chunk recibido por el servidor, complementado con silencio. Los chunks perdidos se marcan como irrecuperables en los metadatos.

### 6.5 Reducción de Ruido

La reducción de ruido se implementa en dos niveles opcionales:

**Nivel 1 — Cliente (tiempo real, opcional):** RNNoise compilado a WebAssembly se ejecuta como un AudioWorklet en el navegador. Procesa el audio del micrófono antes de enviarlo a WebRTC (mejorando la experiencia en vivo) pero NO afecta la grabación local, que se mantiene con audio crudo para preservar la máxima calidad. Este nivel es opcional y se activa por configuración del usuario. Su consumo es mínimo (~2-3% CPU adicional).

**Nivel 2 — Servidor (post-procesamiento):** Durante el procesamiento del worker, se aplica el filtro arnndn de FFmpeg sobre las pistas concatenadas. Esto genera dos versiones de cada pista: una cruda y una con reducción de ruido, para que el editor pueda elegir cuál usar.

### 6.6 Modelo de Datos

| Tabla                 | Campos Principales                                                | Propósito                             |
| --------------------- | ----------------------------------------------------------------- | ------------------------------------- |
| `rooms`               | id, code, host_participant_id, status, created_at                 | Salas de podcast                      |
| `participants`        | id, room_id, display_name, role, status, joined_at                | Participantes de cada sala            |
| `participant_avatars` | id, participant_id, idle_image_s3_key, speaking_image_s3_key      | Imágenes de avatar idle/hablando      |
| `recording_sessions`  | id, room_id, started_at, ended_at, status                         | Sesiones de grabación                 |
| `audio_chunks`        | id, session_id, participant_id, seq_num, ts_start, ts_end, s3_key | Registro de cada chunk subido         |
| `vad_events`          | id, session_id, participant_id, state, ts_ms                      | Eventos de inicio/fin de voz (VAD)    |
| `timestamps_marks`    | id, session_id, participant_id, ts_ms, label                      | Marcas de tiempo creadas por usuarios |
| `processed_tracks`    | id, session_id, participant_id, format, s3_key, duration_ms       | Pistas procesadas finales             |
| `notifications`       | id, session_id, participant_id, type, sent_at, download_url       | Notificaciones de descarga            |

### 6.7 Detección de Voz y Sistema de Avatares

El sistema de avatares animados permite a cada participante subir dos imágenes (idle y hablando) que se alternan automáticamente según la detección de actividad de voz (VAD). Esta funcionalidad tiene doble propósito: mejorar la experiencia visual en vivo durante la sesión y generar datos para la producción de video en post-procesamiento.

#### 6.7.1 Voice Activity Detection (VAD)

La detección de voz se implementa en el cliente usando la Web Audio API nativa del navegador. Se crea un `AnalyserNode` conectado al stream del micrófono que calcula el nivel RMS (Root Mean Square) del audio cada 50-100 milisegundos. El algoritmo compara este nivel contra un umbral configurable para determinar si el participante está hablando o en silencio.

Para evitar parpadeos rápidos entre estados (speaking/silent), se aplica un hold time de 300-500 milisegundos: una vez que se detecta voz, el estado se mantiene como "hablando" durante ese periodo mínimo antes de volver a "silencio". Opcionalmente, la detección se limita al rango de frecuencias de la voz humana (85 Hz - 3000 Hz) para reducir falsos positivos por ruido ambiental.

El consumo de recursos de esta detección es despreciable (< 1% CPU) ya que utiliza la API nativa del navegador sin librerías externas.

#### 6.7.2 Sistema de Avatares

Antes de iniciar la grabación, cada participante puede subir dos imágenes:

- **Imagen idle:** Se muestra cuando el participante no está hablando. Representa al personaje o avatar en estado de reposo.
- **Imagen hablando:** Se muestra cuando el VAD detecta actividad de voz. Representa al personaje con la boca abierta o en actitud de hablar.

Las imágenes se almacenan en S3 asociadas al participante (tabla `participant_avatars`). Se aceptan formatos PNG y GIF con un tamaño máximo de 2 MB por imagen. Si un participante no sube imágenes, se muestra un avatar genérico con la inicial de su nombre y un indicador de borde iluminado como feedback visual alternativo.

La alternancia entre imágenes se realiza con una transición CSS crossfade suave (150ms) para evitar un corte visual abrupto. El estado de VAD de cada participante se distribuye a todos los clientes de la sala vía el evento WebSocket `vad:state`, de manera que todos ven la animación del avatar correspondiente en tiempo real.

#### 6.7.3 Registro de Eventos VAD para Post-Producción

Durante la grabación, cada cambio de estado de voz se registra en la tabla `vad_events` con el timestamp exacto (en milisegundos relativos al inicio de la sesión). Cada registro contiene: participant_id, state (speaking/silent), y ts_ms. Estos datos permiten reconstruir la línea temporal completa de quién habló en qué momento.

Los eventos VAD tienen múltiples usos en post-producción:

- **Generación de video:** Reconstruir la animación de avatares para producir un video del episodio sin necesidad de cámaras.
- **Mapa de actividad:** Visualizar quién habló y cuánto en una línea temporal, útil para el editor.
- **Detección de crosstalk:** Identificar momentos donde dos o más personas hablaron simultáneamente para revisión en edición.
- **Exportación como metadato:** Los eventos se incluyen como archivo JSON junto con las pistas de audio descargables.

---

## 7. Consideraciones de Seguridad

- **Salas con código único:** Códigos de 8 caracteres alfanuméricos generados con `crypto.randomBytes`, lo que da ~2.8 trillones de combinaciones.
- **Tokens de sesión:** Cada participante recibe un JWT de corta duración al unirse a la sala. Todas las comunicaciones WebSocket requieren este token.
- **HTTPS/WSS obligatorio:** Todo el tráfico está cifrado en tránsito. WebRTC usa DTLS/SRTP por defecto.
- **URLs de descarga temporales:** Presigned URLs de S3 con expiración de 72 horas para proteger el contenido.
- **Rate limiting:** Límites en creación de salas y conexiones WebSocket por IP para prevenir abuso.
- **Validación de chunks:** Verificación de tamaño máximo por chunk (5 MB) y formato válido para prevenir carga de datos maliciosos.

---

## 8. Plan de Desarrollo por Hitos

El desarrollo se organiza en iteraciones incrementales. Cada hito produce un entregable funcional que se puede probar con usuarios reales. Las estimaciones asumen un equipo de 2 desarrolladores full-stack.

### 8.1 Hito 1 — Infraestructura y Comunicación Básica

**Duración estimada:** 3-4 semanas

**Objetivo:** Establecer la base técnica del proyecto con comunicación en tiempo real funcional.

- Setup del monorepo con Turborepo (frontend React + backend NestJS con Fastify adapter)
- Docker Compose con PostgreSQL, Dragonfly y SeaweedFS
- NestJS WebSocket Gateway con gestión básica de salas (crear, unirse, salir)
- Signaling WebRTC a través del WebSocket
- Comunicación de voz peer-to-peer entre 2+ participantes
- Interfaz mínima: pantalla de crear/unirse a sala + panel de participantes
- Botón de muteo/desmuteo funcional

**Entregable:** Usuarios pueden crear sala, compartir enlace, y hablar en tiempo real como en una llamada de voz.

### 8.2 Hito 2 — Grabación Local y Envío de Chunks (MVP)

**Duración estimada:** 4-5 semanas

**Objetivo:** Core del producto — grabación individual con envío al servidor.

- Implementar MediaRecorder con timeslice configurable (5-10 segundos)
- Web Worker para buffer y envío de chunks por WebSocket binario
- Servidor: recepción de chunks, metadatos en PostgreSQL, almacenamiento en S3
- Protocolo de ACK para confirmación de recepción de chunks
- Control del anfitrión: botón iniciar/finalizar grabación con cuenta regresiva
- Worker de procesamiento básico: concatenación de chunks por participante con FFmpeg
- Generación de pista individual (WAV) y mezcla final
- Prueba de sonido básica (grabar y reproducir)
- VAD básico (umbral RMS) con registro de eventos en base de datos durante grabación

**Entregable (MVP):** Sesión completa de grabación con pistas individuales, mezcla final y metadatos VAD disponibles para descarga.

### 8.3 Hito 3 — Resiliencia y Reconexiones

**Duración estimada:** 3-4 semanas

**Objetivo:** Garantizar robustez ante fallos de conexión.

- Reconexión automática de WebSocket con backoff exponencial
- Reenvío automático de chunks pendientes tras reconexión
- Restablecimiento de conexiones WebRTC al reconectarse
- Período de gracia post-sesión para chunks pendientes (configurable)
- Generación automática de silencio en huecos de desconexión
- Indicadores visuales de estado de conexión por participante
- Tests de integración simulando desconexiones

**Entregable:** El sistema tolera desconexiones sin pérdida de audio, generando pistas completas y sincronizadas.

### 8.4 Hito 4 — Interacción en Sala y UX

**Duración estimada:** 2-3 semanas

**Objetivo:** Completar las funciones de interacción de la sala.

- Botón de levantar la mano con animación visual
- Botón de marca de tiempo con etiqueta opcional
- Botón de sugerir finalización con notificación al anfitrión
- Prueba de sonido mejorada (reproducir en interfaz + opción de descarga)
- Sistema de avatares: subida de imagen idle/hablando con alternancia por VAD
- Avatar genérico con indicador de borde iluminado como fallback
- Indicador visual de nivel de audio en tiempo real por participante
- Cronómetro de sesión visible durante grabación
- Exportación de eventos VAD como JSON junto con pistas de audio
- Mejoras de UX: transiciones, feedback háptico, sonidos de notificación

**Entregable:** Experiencia completa de sala con avatares animados y todas las interacciones diseñadas.

### 8.5 Hito 5 — Procesamiento Avanzado y Notificaciones

**Duración estimada:** 3-4 semanas

**Objetivo:** Mejorar la calidad del audio procesado y automatizar notificaciones.

- Reducción de ruido con RNNoise (FFmpeg arnndn) en el worker
- Normalización de volumen a -16 LUFS con loudnorm de FFmpeg
- Exportación en múltiples formatos (WAV + MP3)
- Incluir marcas de tiempo en los metadatos del audio exportado
- Sistema de notificaciones por email con enlaces de descarga (presigned URLs)
- Página de descarga con listado de pistas de la sesión
- Limpieza automática de chunks temporales en S3

**Entregable:** Pistas de audio con calidad profesional, notificaciones automáticas y descarga organizada.

### 8.6 Hito 6 — Reducción de Ruido en Cliente y Optimización

**Duración estimada:** 2-3 semanas

**Objetivo:** Mejorar la experiencia en vivo y optimizar rendimiento general.

- RNNoise en WebAssembly como AudioWorklet para comunicación en vivo
- Opción de activar/desactivar reducción de ruido en vivo por participante
- Optimización de consumo de memoria y CPU en el cliente
- Benchmark y profiling de rendimiento bajo carga
- Pruebas de compatibilidad cross-browser (Chrome, Firefox, Edge, Safari)
- Monitorización y logging en producción

**Entregable:** Aplicación optimizada con reducción de ruido en vivo opcional y rendimiento validado.

### 8.7 Hito 7 — Despliegue y Lanzamiento

**Duración estimada:** 2 semanas

**Objetivo:** Puesta en producción estable.

- Configuración de infraestructura cloud (VPS + S3 + dominio + SSL)
- Pipeline CI/CD con GitHub Actions (lint, test, build, deploy)
- STUN/TURN server propio o servicio (coturn)
- Health checks y alertas
- Documentación de usuario y guía de uso
- Beta testing con sesiones de podcast reales

**Entregable:** Plataforma en producción lista para uso real.

---

## 9. Matriz de Trazabilidad: Requerimientos vs Hitos

La siguiente matriz permite rastrear qué requerimientos funcionales y no funcionales se abordan en cada hito del plan de desarrollo. El símbolo ● indica cobertura principal (el requerimiento se implementa en ese hito) y ○ indica cobertura parcial o complementaria.

### 9.1 Requerimientos Funcionales

| Req.  | Descripción                                  | H1  | H2  | H3  | H4  | H5  | H6  | H7  |
| ----- | -------------------------------------------- | --- | --- | --- | --- | --- | --- | --- |
| RF-01 | Crear sala con enlace de invitación          | ●   |     |     |     |     |     |     |
| RF-02 | Comunicación de voz en tiempo real           | ●   |     | ○   |     |     |     |     |
| RF-03 | Grabación local de audio individual          |     | ●   |     |     |     |     |     |
| RF-04 | Envío de chunks al servidor                  |     | ●   | ○   |     |     |     |     |
| RF-05 | Almacenamiento en S3                         |     | ●   |     |     |     |     |     |
| RF-06 | Control anfitrión (inicio/fin + countdown)   |     | ●   |     |     |     |     |     |
| RF-07 | Prueba de sonido (escuchar/descargar)        |     | ○   |     | ●   |     |     |     |
| RF-08 | Muteo/desmuteo de micrófono                  | ●   |     |     |     |     |     |     |
| RF-09 | Levantar la mano                             |     |     |     | ●   |     |     |     |
| RF-10 | Marca de tiempo (timestamp)                  |     |     |     | ●   | ○   |     |     |
| RF-11 | Sugerencia de finalización                   |     |     |     | ●   |     |     |     |
| RF-12 | Reconexión + silencio automático             |     |     | ●   |     |     |     |     |
| RF-13 | Mezcla final de todos los participantes      |     | ●   |     |     | ○   |     |     |
| RF-14 | Notificación con enlace de descarga          |     |     |     |     | ●   |     |     |
| RF-15 | Período de gracia post-sesión                |     |     | ●   |     |     |     |     |
| RF-16 | Reducción de ruido                           |     |     |     |     | ●   | ○   |     |
| RF-17 | Detección de actividad de voz (VAD)          |     | ●   |     | ○   |     |     |     |
| RF-18 | Avatares animados (idle/hablando)            |     |     |     | ●   |     |     |     |
| RF-19 | Registro de eventos VAD para post-producción |     | ●   |     | ○   |     |     |     |

### 9.2 Requerimientos No Funcionales

Los requerimientos no funcionales son transversales y se trabajan progresivamente a lo largo de múltiples hitos:

| Req.   | Descripción                         | H1  | H2  | H3  | H4  | H5  | H6  | H7  |
| ------ | ----------------------------------- | --- | --- | --- | --- | --- | --- | --- |
| RNF-01 | Bajo consumo de recursos en cliente | ○   | ○   |     |     |     | ●   |     |
| RNF-02 | Latencia < 300ms                    | ●   |     | ○   |     |     | ○   |     |
| RNF-03 | Tolerancia a pérdida de paquetes    |     | ○   | ●   |     |     |     |     |
| RNF-04 | Disponibilidad > 99.5%              |     |     |     |     |     |     | ●   |
| RNF-05 | Compatibilidad cross-browser        | ○   | ○   |     |     |     | ●   |     |
| RNF-06 | Procesamiento < 2x duración         |     |     |     |     | ●   | ○   |     |
| RNF-07 | Escalabilidad (múltiples salas)     |     |     |     |     |     |     | ●   |

### 9.3 Resumen de Cobertura por Hito

| Hito                 | RF Principales                                  | RF Parciales | RNF Abordados                  |
| -------------------- | ----------------------------------------------- | ------------ | ------------------------------ |
| H1 - Infraestructura | RF-01, RF-02, RF-08                             | —            | RNF-02, RNF-05                 |
| H2 - Grabación (MVP) | RF-03, RF-04, RF-05, RF-06, RF-13, RF-17, RF-19 | RF-07        | RNF-01, RNF-03, RNF-05         |
| H3 - Resiliencia     | RF-12, RF-15                                    | RF-02, RF-04 | RNF-03                         |
| H4 - Interacción UX  | RF-07, RF-09, RF-10, RF-11, RF-18               | RF-17, RF-19 | —                              |
| H5 - Procesamiento   | RF-14, RF-16                                    | RF-10, RF-13 | RNF-06                         |
| H6 - Optimización    | —                                               | RF-16        | RNF-01, RNF-02, RNF-05, RNF-06 |
| H7 - Despliegue      | —                                               | —            | RNF-04, RNF-07                 |

> **Nota:** Esta matriz debe actualizarse al inicio de cada hito durante la planificación del sprint, incorporando cambios en alcance o repriorización de requerimientos según el feedback de las iteraciones anteriores.

---

## 10. Iteraciones Futuras (Post-Lanzamiento)

Las siguientes funcionalidades se planean para iteraciones posteriores al lanzamiento, según demanda y feedback de usuarios:

| Funcionalidad               | Descripción                                                                      | Complejidad |
| --------------------------- | -------------------------------------------------------------------------------- | ----------- |
| Sistema de cuentas          | Registro/login con email o OAuth, historial de sesiones                          | Media       |
| Avatares animados avanzados | Multi-frame con modulación por volumen (3-4 estados de boca), movimiento de ojos | Media       |
| Generación de video         | Renderizado automático de video con avatares animados usando eventos VAD         | Alta        |
| App móvil                   | Versión React Native o Capacitor para iOS/Android                                | Alta        |
| Captura de video            | Grabación de cámara individual + composición automática                          | Alta        |
| Post-procesamiento auto     | Mezcla inteligente, compresores, EQ automático                                   | Media       |
| Transcripción automática    | Speech-to-text con Whisper por participante                                      | Media       |
| Chat de texto en sala       | Mensajes de texto durante la sesión                                              | Baja        |
| Integración DAW             | Exportar proyecto compatible con Audacity / Reaper / Logic                       | Media       |
| Grabación programada        | Agendar sesiones con recordatorios automáticos                                   | Baja        |
| Panel de administración     | Dashboard con historial de sesiones, estadísticas de uso                         | Media       |

---

## 11. Resumen del Timeline

Estimación total desde inicio hasta lanzamiento: **19-25 semanas (~5-6 meses)** con un equipo de 2 desarrolladores.

| Hito | Nombre                                       | Duración | Acumulado |
| ---- | -------------------------------------------- | -------- | --------- |
| 1    | Infraestructura y Comunicación Básica        | 3-4 sem  | 3-4 sem   |
| 2    | Grabación y Envío de Chunks (MVP)            | 4-5 sem  | 7-9 sem   |
| 3    | Resiliencia y Reconexiones                   | 3-4 sem  | 10-13 sem |
| 4    | Interacción en Sala y UX                     | 2-3 sem  | 12-16 sem |
| 5    | Procesamiento Avanzado y Notificaciones      | 3-4 sem  | 15-20 sem |
| 6    | Reducción de Ruido en Cliente y Optimización | 2-3 sem  | 17-23 sem |
| 7    | Despliegue y Lanzamiento                     | 2 sem    | 19-25 sem |

> **Nota:** El MVP funcional (Hitos 1 + 2) se alcanza en aproximadamente 7-9 semanas, lo que permite validar la propuesta con usuarios reales de manera temprana y ajustar el rumbo según el feedback recibido.

---

## 12. Estimación de Costos de Infraestructura

Estimación mensual para un escenario de uso moderado (10 sesiones/semana, 5 participantes, 1 hora promedio por episodio):

| Servicio               | Especificación                                | Costo Estimado/mes |
| ---------------------- | --------------------------------------------- | ------------------ |
| VPS (API + WebSocket)  | 2 vCPU, 4 GB RAM (ej. Hetzner, DigitalOcean)  | $15 - $25 USD      |
| VPS (Worker)           | 2 vCPU, 4 GB RAM (procesamiento FFmpeg)       | $15 - $25 USD      |
| PostgreSQL             | Managed o en VPS principal                    | $0 - $15 USD       |
| Dragonfly              | Managed o en VPS principal                    | $0 - $10 USD       |
| S3 Storage             | ~100 GB/mes (chunks + procesados)             | $2 - $5 USD        |
| TURN Server            | coturn self-hosted o servicio (Twilio/Xirsys) | $0 - $30 USD       |
| Dominio + SSL          | Let's Encrypt (gratuito) + dominio            | $1 - $2 USD        |
| Email (notificaciones) | Resend / SendGrid tier gratuito               | $0 USD             |
|                        | **TOTAL ESTIMADO**                            | **$33 - $112 USD** |

> **Nota:** Estos costos corresponden a una operación a pequeña escala. Para self-hosting completo (SeaweedFS en lugar de S3, coturn propio), el costo se reduce significativamente al precio de los VPS.

---

## 13. Conclusiones

PodSync propone una solución integral al problema de la grabación remota de podcasts, abordando las limitaciones fundamentales del flujo actual basado en Discord + OBS. Los principios de diseño clave son:

1. **Grabación local primero:** Al grabar directamente del micrófono en cada dispositivo, la calidad del audio es independiente de la conexión a Internet.
2. **Envío incremental:** Los chunks de 5 segundos minimizan el riesgo de pérdida de audio y permiten recuperación granular.
3. **Separación de concerns:** La comunicación en vivo (WebRTC) y la grabación (MediaRecorder) son flujos independientes, evitando que problemas en uno afecten al otro.
4. **Tolerancia a fallos:** El sistema de buffers, ACKs, y generación de silencio asegura que siempre se produce un resultado utilizable.
5. **Bajo consumo de recursos:** El uso de Web Workers, codecs eficientes (Opus), y WebRTC P2P mantiene la carga del cliente en niveles mínimos.

Con un desarrollo incremental de 5-6 meses y un MVP disponible en ~2 meses, el proyecto permite validación temprana y mejora continua basada en uso real. La arquitectura está diseñada para evolucionar hacia funcionalidades futuras (video, cuentas, apps móviles) sin reescrituras fundamentales.

---

*Fin del documento*
