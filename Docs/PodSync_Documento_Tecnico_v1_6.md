# PodSync — Documento Técnico de Diseño

**Plataforma de Grabación Remota para Podcasts**
**Versión 1.6 — Abril 2026**
**CONFIDENCIAL**

---

## Índice de Contenido

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Problemática Actual](#2-problemática-actual)
3. [Análisis de Requerimientos](#3-análisis-de-requerimientos)
4. [Selección del Stack Tecnológico](#4-selección-del-stack-tecnológico)
5. [Arquitectura del Sistema](#5-arquitectura-del-sistema)
6. [Diseño Detallado de Componentes](#6-diseño-detallado-de-componentes)
7. [Flujo de Identidad y Autenticación](#7-flujo-de-identidad-y-autenticación)
8. [Consideraciones de Seguridad](#8-consideraciones-de-seguridad)
9. [Estrategia de Testing](#9-estrategia-de-testing)
10. [Observabilidad y Monitorización](#10-observabilidad-y-monitorización)
11. [Plan de Desarrollo por Hitos](#11-plan-de-desarrollo-por-hitos)
12. [Matriz de Trazabilidad: Requerimientos vs Hitos](#12-matriz-de-trazabilidad-requerimientos-vs-hitos)
13. [Iteraciones Futuras (Post-Lanzamiento)](#13-iteraciones-futuras-post-lanzamiento)
14. [Resumen del Timeline](#14-resumen-del-timeline)
15. [Estimación de Costos de Infraestructura](#15-estimación-de-costos-de-infraestructura)
16. [Conclusiones](#16-conclusiones)

---

## Changelog v1.5 → v1.6

| # | Cambio | Origen | Secciones afectadas |
|---|--------|--------|-------------------|
| 1 | Múltiples sesiones de grabación por sala (secuenciales, no simultáneas). Estado `rooms.status` simplificado a `active / closed` | ADR-001 | §3.1, §5.3, §6.2.1, §6.2.2, §6.6, §11 |
| 2 | Límites de tiempo configurables: `max_room_duration_ms` y `max_recording_duration_ms` en `room_settings`, enforcement server-side con BullMQ delayed jobs | ADR-001 | §3.1, §6.2.1, §6.2.2, §6.4, §6.6, §11 |
| 3 | Warnings de tiempo al cliente vía WebSocket (`room:time-warning`, `recording:time-warning`, `*:time-expired`) | ADR-001 | §6.2.2, §11 |
| 4 | Room TTL respeta grace period antes de cerrar la sala | ADR-001 | §6.4 |
| 5 | Autenticación básica para hosts con Passport.js (email+password, argon2). Guests permanecen efímeros. La restricción de §3.3 v1.5 ("sin sistema de cuentas en el MVP") se reemplaza por autenticación obligatoria para hosts | ADR-002 + decisión de diseño posterior | §3.3, §6.2.1, §6.6, §7, §8, §11 |
| 6 | Tabla `users` en el schema desde H1 con campos mínimos. `rooms.owner_user_id` con FK real a `users` (nullable para desarrollo local) | ADR-002 (modificado) | §6.6 |
| 7 | Asimetría de identidad host/guest como principio de diseño explícito: el host requiere cuenta persistente, el guest es efímero por defecto con cuenta opcional futura | ADR-002 | §7 |
| 8 | `participants.user_id` nullable como puente de vinculación retroactiva para guests que creen cuenta en el futuro | ADR-002 | §6.6 |
| 9 | Guard de autorización del host (`JwtHostGuard`) encapsulado con lógica reemplazable para facilitar evolución del modelo de auth | ADR-002 | §7 |
| 10 | Endpoint `GET /api/rooms/:id/sessions` para listar sesiones de una sala | ADR-001 | §6.2.1 |
| 11 | Recovery de delayed jobs tras restart del servidor documentado como requisito | ADR-001 | §6.4, §9.2 |
| 12 | Máximo global de duración como hard limit cuando no existe plan asociado al host (`MAX_RECORDING_DURATION_HARD_LIMIT`, `MAX_ROOM_DURATION_HARD_LIMIT` en env vars) | Decisión de diseño | §6.4, §8 |

**Nota sobre ADRs anteriores:** Los documentos ADR-001 (Múltiples Sesiones y Límites de Tiempo) y ADR-002 (Asimetría de Identidad Host/Guest) quedan como artefactos históricos del proceso de diseño. Sus decisiones están completamente integradas en este TDD. El TDD v1.6 es la única fuente de verdad del proyecto.

---

## 1. Resumen Ejecutivo

PodSync es una plataforma web diseñada para la grabación remota de podcasts con captura de audio individual por participante. A diferencia del flujo actual basado en Discord + OBS, donde el audio se mezcla en una sola pista, PodSync permite que cada participante grabe localmente en su dispositivo y envíe fragmentos al servidor en segundo plano, resultando en pistas de audio independientes y de alta calidad que facilitan la edición y post-producción.

La comunicación en vivo entre participantes se realiza mediante un servidor SFU (Selective Forwarding Unit) basado en mediasoup, que ofrece baja latencia y mejor escalabilidad que una topología peer-to-peer pura, al tiempo que reduce la carga de CPU en los clientes.

La plataforma implementa un modelo de identidad asimétrico: los hosts (creadores de sala) requieren una cuenta persistente con autenticación por email y contraseña, mientras que los guests (invitados) participan de forma efímera mediante un enlace de invitación sin necesidad de registro. Este diseño protege los recursos del servidor y establece la base para un modelo comercial futuro con planes y límites de uso.

Las salas soportan múltiples sesiones de grabación secuenciales, permitiendo grabar varios episodios o repetir tomas sin recrear la sala ni reinvitar participantes. Cada sesión de grabación y cada sala tienen límites de tiempo configurables, cuyo enforcement se realiza exclusivamente en el servidor.

Este documento detalla la arquitectura, el stack tecnológico, los flujos de datos, el modelo de autenticación, la estrategia de testing, y el plan de desarrollo incremental organizado en hitos para llevar el producto desde su MVP hasta una solución completa.

---

## 2. Problemática Actual

### 2.1 Descripción del Problema

El flujo actual de grabación presenta las siguientes deficiencias:

- **Audio mezclado en una sola pista:** OBS captura la salida de audio de Discord como un único stream, mezclando todas las voces. Esto imposibilita la normalización individual del volumen.
- **Pérdida de diálogos:** Cuando dos o más personas hablan simultáneamente, las voces con menor volumen se pierden al estar mezcladas.
- **Inestabilidad de conexión:** Las fluctuaciones de red de los participantes afectan la calidad del audio grabado, generando cortes y artefactos en la pista final.
- **Edición compleja:** Sin pistas separadas, la post-producción requiere técnicas avanzadas (noise gates, compresores laterales) que no siempre logran resultados óptimos.

### 2.2 Solución Propuesta

Desarrollar una aplicación web que permita a los participantes reunirse en una sala virtual donde se puedan comunicar en tiempo real mediante un SFU (mediasoup), mientras que en paralelo cada cliente graba su propio audio localmente usando la MediaRecorder API del navegador. Estos fragmentos de audio se envían de forma incremental al servidor vía WebSocket, que a su vez los almacena en un servicio compatible con S3 (SeaweedFS). Al finalizar cada sesión de grabación, se procesan las pistas individuales y se genera también una mezcla consolidada. Una sala puede albergar múltiples sesiones de grabación secuenciales.

---

## 3. Análisis de Requerimientos

### 3.1 Requerimientos Funcionales

| ID | Requerimiento | Prioridad |
|----|--------------|-----------|
| RF-01 | Crear sala de podcast con código/enlace de invitación (requiere host autenticado) | Alta |
| RF-02 | Comunicación de voz en tiempo real entre participantes (hasta 5) | Alta |
| RF-03 | Grabación local de audio individual en cada dispositivo | Alta |
| RF-04 | Envío de fragmentos de audio (chunks) al servidor en segundo plano | Alta |
| RF-05 | Almacenamiento de chunks en servicio compatible con S3 | Alta |
| RF-06 | Control del anfitrión: iniciar/finalizar grabación con cuenta regresiva | Alta |
| RF-07 | Prueba de sonido individual antes de iniciar grabación (escuchar/descargar) | Alta |
| RF-08 | Botón de muteo/desmuteo de micrófono | Alta |
| RF-09 | Botón de levantar la mano (aviso visual a todos) | Media |
| RF-10 | Botón de marca de tiempo (timestamp bookmark) | Media |
| RF-11 | Botón de sugerencia de finalización de sesión | Media |
| RF-12 | Reconexión automática con generación de silencio en pista del ausente | Alta |
| RF-13 | Generación de pista final con mezcla de todos los participantes | Alta |
| RF-14 | Notificación a posteriori con enlace de descarga cuando audios estén listos | Media |
| RF-15 | Periodo de gracia post-sesión para recibir chunks pendientes | Alta |
| RF-16 | Reducción de ruido opcional en el audio capturado | Baja |
| RF-17 | Detección de actividad de voz (VAD) con indicador visual por participante | Media |
| RF-18 | Avatares animados: subir imagen idle/hablando con alternancia por VAD | Media |
| RF-19 | Registro de eventos VAD (timestamps inicio/fin de voz) para post-producción | Media |
| RF-20 | Registro de usuario host con email y contraseña | Alta |
| RF-21 | Inicio de sesión (login) para hosts con JWT de sesión larga | Alta |
| RF-22 | Múltiples sesiones de grabación secuenciales por sala (no simultáneas) | Alta |
| RF-23 | Límite de tiempo configurable por sesión de grabación con enforcement server-side | Alta |
| RF-24 | Límite de tiempo configurable por sala (TTL) con enforcement server-side | Alta |
| RF-25 | Warnings de tiempo al cliente cuando se acercan los límites | Media |
| RF-26 | Listado de sesiones de grabación por sala | Media |
| RF-27 | Cierre automático de sala por expiración de TTL respetando grace period | Alta |

### 3.2 Requerimientos No Funcionales

| ID | Requerimiento | Métrica |
|----|--------------|---------|
| RNF-01 | Bajo consumo de recursos en el cliente | < 10% CPU, < 150 MB RAM |
| RNF-02 | Latencia de comunicación en tiempo real | < 300 ms (audio conversacional) |
| RNF-03 | Tolerancia a pérdida de paquetes | Recuperación sin pérdida de grabación |
| RNF-04 | Disponibilidad del servicio | > 99.5% uptime |
| RNF-05 | Compatibilidad de navegadores | Chrome, Firefox, Edge, Safari |
| RNF-06 | Tiempo de procesamiento post-sesión | < 2x la duración del episodio |
| RNF-07 | Escalabilidad | Múltiples salas concurrentes |

### 3.3 Restricciones

- Máximo 5 participantes por sala.
- Plataforma web (navegador) como target principal del MVP.
- Los hosts requieren cuenta persistente (email + contraseña) para crear salas. Los guests participan de forma efímera mediante enlace de invitación, sin necesidad de registro.
- Solo puede existir una sesión de grabación activa por sala en un momento dado. El host no puede iniciar una nueva grabación mientras haya una sesión en estado `recording` o `grace_period`.
- Los límites de tiempo de sala y grabación se aplican mediante hard limits globales configurables por variable de entorno cuando no existe un plan asociado al host. En el futuro, estos hard limits se reemplazan por los topes definidos en el plan comercial del usuario.
- El audio procesado no estará disponible para descarga inmediata.

---

## 4. Selección del Stack Tecnológico

### 4.1 Análisis Comparativo

Se analizaron las opciones vigentes para cada componente del sistema, priorizando eficiencia, ecosistema, y bajo consumo de recursos.

#### 4.1.1 Frontend

| Opción | Ventajas | Desventajas | Veredicto |
|--------|----------|-------------|-----------|
| React + TypeScript | Ecosistema maduro, amplia comunidad, excelente soporte para Web Audio API | Bundle size mayor que alternativas más ligeras | **SELECCIONADO** |
| SvelteKit | Bundle más pequeño, reactivo por defecto | Ecosistema más pequeño para integraciones media | Alternativa viable |
| Vue 3 | API de composición moderna, buen rendimiento | Menos librerías específicas para audio | Descartado |

#### 4.1.2 Backend

| Opción | Ventajas | Desventajas | Veredicto |
|--------|----------|-------------|-----------|
| NestJS (Fastify adapter) | Arquitectura modular, inyección de dependencias, WebSocket Gateways nativos, mismo lenguaje que frontend | Mayor consumo de memoria base (~30-60 MB extra vs Fastify puro) | **SELECCIONADO** |
| Node.js (Fastify puro) | Mínimo overhead, alto throughput, bajo consumo de memoria | Sin estructura opinada, requiere más código de organización manual | Evaluado, descartado por menor mantenibilidad |
| Go | Alto rendimiento, concurrencia nativa con goroutines, bajo consumo de memoria | Lenguaje diferente al frontend, curva de aprendizaje | Alternativa para escalar servicios auxiliares |
| Python (FastAPI) | Excelente para procesamiento de audio (scipy, librosa) | Mayor consumo de memoria, GIL limita concurrencia | **SELECCIONADO para servicio de procesamiento de audio** |

#### 4.1.3 Comunicación en Tiempo Real

| Opción | Ventajas | Desventajas | Veredicto |
|--------|----------|-------------|-----------|
| WebRTC (peer-to-peer mesh) | Baja latencia, sin pasar por servidor, cifrado E2E | Con N participantes, cada cliente mantiene N-1 conexiones. A 5 peers: 4 encoders + 4 decoders por cliente, carga de CPU excesiva en hardware modesto. Complejidad de NAT traversal | Descartado por problemas de escalabilidad en mesh ≥ 4 participantes |
| **mediasoup (SFU)** | Cada cliente envía 1 stream al servidor y recibe N-1. Reduce carga CPU del cliente ~75% vs mesh. Control centralizado de calidad. Arquitectura extensible a video futuro | Requiere servidor dedicado con mayor ancho de banda de salida | **SELECCIONADO** |
| LiveKit | SFU open-source completo, SDKs multiplataforma | Mayor complejidad operacional, opinionated | Evaluado para iteraciones futuras |

**Justificación del cambio de P2P a SFU:** En una topología full mesh con 5 participantes, cada cliente debe mantener 4 conexiones RTCPeerConnection simultáneas, codificando y decodificando 4 streams de audio. Combinado con MediaRecorder, VAD, y potencial RNNoise WASM, el cumplimiento de RNF-01 (< 10% CPU, < 150 MB RAM) no es viable en hardware de consumo. mediasoup reduce la carga del cliente a 1 uplink + N-1 downlinks sin re-encoding, y centraliza el control de calidad y la gestión de conexiones.

#### 4.1.4 Almacenamiento

| Opción | Ventajas | Desventajas | Veredicto |
|--------|----------|-------------|-----------|
| **SeaweedFS (self-hosted)** | Compatible con S3 API, licencia Apache 2.0, ligero, bajo consumo, misma instancia en dev y prod elimina bugs por divergencia de comportamiento | Comunidad más pequeña, menos documentación empresarial, responsabilidad operacional propia | **SELECCIONADO (dev y producción)** |
| AWS S3 | Alta disponibilidad, escalabilidad automática | Costos variables, diferencias sutiles con SeaweedFS en multipart upload y consistency model | Descartado para evitar divergencia dev/prod |
| Cloudflare R2 | Compatible S3, sin costos de egress | Menor ecosistema de herramientas | Alternativa futura si se necesita CDN |

**Nota:** Para mitigar el riesgo de lock-in y facilitar una migración futura, toda la interacción con almacenamiento de objetos se realizará a través de una interfaz de abstracción (`StoragePort`) en el backend. Esto permite cambiar el proveedor sin modificar la lógica de negocio.

#### 4.1.5 Autenticación

| Opción | Ventajas | Desventajas | Veredicto |
|--------|----------|-------------|-----------|
| **Passport.js (@nestjs/passport)** | Integración nativa con NestJS, estrategias modulares (Local, JWT, OAuth futuro), zero overhead operacional, sin servicios adicionales | Requiere implementar manualmente reset de password, verificación de email | **SELECCIONADO** |
| Keycloak | SSO completo, OAuth2/OIDC, UI de administración, MFA, federation LDAP/SAML | 500 MB-1 GB RAM, requiere DB dedicada, complejidad operacional alta, sobredimensionado para etapa actual | Descartado para MVP. Reevaluar si se necesita SSO empresarial o federation con identity providers corporativos |
| Casdoor | Similar a Keycloak pero más ligero (Go), UI moderna | 200-400 MB RAM, servicio adicional en Docker Compose, documentación irregular, comunidad más pequeña | Descartado para MVP por mismas razones que Keycloak en menor medida |

**Justificación de Passport sobre identity providers externos:** El requisito actual es un "candado en la puerta" — autenticación básica para hosts que proteja los recursos del servidor. Passport resuelve esto con ~3-5 días de implementación, 0 MB de RAM adicional, y 0 servicios extra en Docker Compose. Keycloak o Casdoor resuelven problemas que PodSync no tiene todavía (SSO multi-aplicación, federation corporativa, MFA). La migración futura de Passport a un provider externo es limpia si el `AuthModule` usa el patrón Strategy, que es exactamente cómo Passport funciona.

### 4.2 Stack Seleccionado (Resumen)

| Componente | Tecnología | Justificación |
|-----------|-----------|---------------|
| Frontend | React 19 + TypeScript + Vite | Madurez del ecosistema, excelente soporte Web APIs |
| UI Framework | Tailwind CSS + shadcn/ui | Desarrollo rápido, consistencia visual, bajo overhead |
| Backend (API/WebSocket) | NestJS + Fastify adapter + @nestjs/websockets | Arquitectura modular, DI, WebSocket Gateways, mismo lenguaje |
| Backend (Procesamiento) | Python + FFmpeg | Ecosistema líder en procesamiento de audio |
| Autenticación | Passport.js (@nestjs/passport) + argon2 | Integración nativa NestJS, zero overhead, estrategias modulares |
| Comunicación en vivo | mediasoup (SFU) | Baja carga en clientes, escalable a 5+ participantes, control centralizado |
| Señalización | NestJS WebSocket Gateway (ws) | Integrado con el framework, decoradores tipados |
| Almacenamiento objetos | SeaweedFS (dev y producción) | API S3-compatible, Apache 2.0, paridad dev/prod |
| Abstracción storage | `StoragePort` interface (NestJS) | Desacopla lógica de negocio del proveedor S3 |
| Base de datos | PostgreSQL + Prisma ORM | Robusto, relacional, excelente con Node.js |
| Cola de tareas | BullMQ + Dragonfly | Procesamiento asíncrono confiable, multi-threaded |
| Bridge Cola→Worker | HTTP (NestJS consumer → Python REST) | Desacoplamiento total entre servicios (ver §6.3) |
| Procesamiento audio | FFmpeg + RNNoise (WASM) | Estándar de la industria + reducción de ruido eficiente |
| Reverse Proxy / SSL | Caddy | SSL automático con Let's Encrypt, config mínima |
| Monorepo | Turborepo + pnpm + Corepack | Cache inteligente de builds, task pipeline, eficiente en disco |
| Contenerización | Docker + Docker Compose | Entorno reproducible, fácil despliegue |
| CI/CD | GitHub Actions | Integración nativa con repositorios |
| Logging | pino (NestJS) | Structured logging, alto rendimiento, JSON nativo |

---

## 5. Arquitectura del Sistema

### 5.1 Visión General

La arquitectura se organiza en capas claramente separadas siguiendo un patrón de microservicios ligeros, donde cada componente tiene una responsabilidad bien definida:

1. **Capa de Cliente (Browser):** Captura de audio local, grabación con MediaRecorder, envío de chunks, conexión al SFU para comunicación en vivo.
2. **Capa de Señalización y API (NestJS):** Gestión de salas, autenticación (Passport para hosts, JWT efímeros para guests), WebSocket Gateways para signaling y coordinación, recepción de chunks, integración con mediasoup para transporte de media. Organizado en módulos: `AuthModule`, `UsersModule`, `RoomsModule`, `RecordingModule`, `SignalingModule`, `ChunksModule`, `MediaModule`.
3. **Capa de Media (mediasoup):** SFU que recibe el audio de cada participante y lo distribuye selectivamente a los demás. Se ejecuta como un proceso integrado con NestJS (misma máquina, comunicado por IPC via mediasoup Node.js API).
4. **Capa de Almacenamiento:** SeaweedFS (S3-compatible) para chunks de audio y archivos procesados, PostgreSQL para metadatos de sesiones y cuentas de usuario.
5. **Capa de Procesamiento (Worker Python):** Concatenación de chunks, generación de silencio, reducción de ruido, mezcla final. Se comunica con NestJS vía HTTP.
6. **Capa de Notificación:** Aviso por email/webhook cuando los audios están listos para descarga.

### 5.2 Diagrama de Componentes

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                              CLIENTE (Browser)                                │
│  ┌────────────────┐  ┌───────────────┐  ┌───────────────┐  ┌──────────────┐  │
│  │  mediasoup      │  │ MediaRecorder │  │  WebSocket    │  │   React UI   │  │
│  │  Client SDK     │  │ (local rec)   │  │ (signaling +  │  │  (interface) │  │
│  │  (live comms)   │  │               │  │  chunks)      │  │              │  │
│  └───────┬─────────┘  └───────┬───────┘  └───────┬───────┘  └──────────────┘  │
└──────────┼────────────────────┼──────────────────┼────────────────────────────┘
           │ (1 uplink)         │ (chunks)         │ (signaling + events)
           │                    │                  │
┌──────────┴────────────────────┴──────────────────┴────────────────────────────┐
│                     SERVIDOR (NestJS + Fastify adapter)                        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌───────────────────────┐ │
│  │ Auth Module  │ │ WS Gateway   │ │ Chunk        │ │ Room Manager          │ │
│  │ (Passport +  │ │ (signaling)  │ │ Receiver     │ │ + Settings + Sessions │ │
│  │  JWT)        │ │              │ │              │ │ + Time Limits         │ │
│  └──────────────┘ └──────┬───────┘ └──────┬───────┘ └───────────────────────┘ │
│                          │                │                                    │
│  ┌──────────────────────────────────┐     │                                    │
│  │ mediasoup Worker (SFU)           │     │                                    │
│  │ (Router → Transports → Producers│     │                                    │
│  │  & Consumers per participant)    │     │                                    │
│  └──────────────────────────────────┘     │                                    │
└───────────────────────────────────────────┼────────────────────────────────────┘
           │                    │            │
    ┌──────┴──────┐    ┌───────┴───────┐  ┌─┴────────────┐
    │ PostgreSQL  │    │  SeaweedFS    │  │ BullMQ +     │
    │ (metadata + │    │  (S3-compat)  │  │ Dragonfly    │
    │  users)     │    │               │  │              │
    └─────────────┘    └───────────────┘  └──────┬───────┘
                                                  │ HTTP trigger
                                          ┌───────┴────────┐
                                          │ Audio Worker   │
                                          │ (Python/FFmpeg)│
                                          │ REST API       │
                                          └────────────────┘
```

### 5.3 Flujo de Datos Principal

El flujo de datos durante una sesión de grabación sigue estas fases:

**Fase 1 — Pre-sesión:** El host, previamente autenticado con su cuenta persistente (ver §7), crea una sala y recibe el `room_id` y un enlace de invitación. Al crear la sala se programa un delayed job de Room TTL si `max_room_duration_ms` está configurado. Los guests se unen proporcionando su nombre y opcionalmente un email a través del enlace de invitación, reciben un JWT efímero con `role: guest`, y se conectan al SFU (mediasoup) para comunicación en vivo. Realizan pruebas de sonido.

**Fase 2 — Inicio de grabación:** El host presiona el botón de iniciar grabación. El servidor valida que no existe otra sesión activa en la sala y que el TTL restante de la sala es suficiente (> 5 minutos). Se crea una nueva `recording_session` y se programa un delayed job de Recording Limit si `max_recording_duration_ms` está configurado. Se emite un evento por WebSocket a todos los clientes mostrando una cuenta regresiva sincronizada (3, 2, 1). Al llegar a cero, cada cliente inicia su MediaRecorder local.

**Fase 3 — Grabación activa:** Cada cliente genera chunks de audio cada 5 segundos (configurable). Los chunks se encolan localmente en un buffer y se envían al servidor vía WebSocket binary frames. El servidor los recibe, les asigna metadatos (timestamp relativo, participante, número de secuencia) y los sube a SeaweedFS. Si se acerca el límite de tiempo de grabación, el servidor emite un warning 5 minutos antes.

**Fase 4 — Finalización:** El host presiona finalizar (o el Recording Limit expira automáticamente), se emite cuenta regresiva de cierre, y al llegar a cero cada cliente envía su último chunk con flag de finalización. El servidor cancela el Recording Limit delayed job si existe y espera un periodo de gracia configurable (5 minutos por defecto) para recibir chunks pendientes de participantes con conexión inestable. La sala permanece activa — el host puede iniciar una nueva sesión de grabación.

**Fase 5 — Procesamiento:** El servicio NestJS encola un job en BullMQ. Un consumer interno dequeue el job y dispara una petición HTTP al worker Python con los metadatos de la sesión. El worker descarga los chunks de SeaweedFS, los concatena por participante respetando timestamps, genera silencio donde haya huecos por desconexión, aplica reducción de ruido opcional, y produce la pista individual y la mezcla final en el formato configurado (FLAC por defecto).

**Fase 6 — Notificación:** Una vez procesados los audios, se notifica a los participantes que proporcionaron email (vía email) con el enlace de descarga temporal. Si múltiples sesiones de la misma sala completan en un rango corto (< 5 minutos), las notificaciones se agrupan en un solo email. Alternativamente, se soporta webhook como canal de notificación.

**Fase 7 — Cierre de sala:** El host cierra la sala manualmente, o el Room TTL expira. Si el TTL expira durante una grabación activa, el sistema fuerza stop con countdown normal → grace period → processing, y luego cierra la sala. Las pistas procesadas siguen disponibles para descarga hasta que expire la retención.

---

## 6. Diseño Detallado de Componentes

### 6.1 Cliente (Frontend)

#### 6.1.1 Captura de Audio Local

Se utilizará la API `navigator.mediaDevices.getUserMedia()` para obtener el stream del micrófono del usuario. Este stream alimenta dos flujos paralelos:

- **mediasoup (SFU):** El stream se conecta a un `mediasoup-client` Transport que envía el audio al servidor SFU. El SFU se encarga de distribuirlo a los demás participantes. Cada cliente mantiene un único Producer (uplink) y N-1 Consumers (downlinks), reduciendo significativamente la carga de CPU frente a un mesh P2P.
- **MediaRecorder:** El mismo stream se graba localmente usando MediaRecorder con codec Opus en contenedor WebM (`audio/webm;codecs=opus`). Se configura con `timeslice` de 5000ms para generar chunks periódicos.

Esta arquitectura dual garantiza que la grabación es independiente de la calidad de la conexión: incluso si el SFU sufre degradación, la grabación local mantiene la calidad original del micrófono.

#### 6.1.2 Buffer y Envío de Chunks

Los chunks generados por MediaRecorder se encolan en un buffer local implementado como un array en memoria. Un worker de envío (implementado como un Web Worker para no bloquear el hilo principal) toma chunks del buffer y los envía por WebSocket en formato binario.

El protocolo de envío incluye:

- **Header binario de 40 bytes:**
  - `session_id`: 16 bytes (UUID, binary format)
  - `participant_id`: 16 bytes (UUID, binary format)
  - `sequence_number`: 4 bytes (uint32, big-endian)
  - `timestamp_ms`: 4 bytes (uint32, big-endian, **relativo al inicio de la sesión de grabación**, no epoch. Esto permite hasta ~49.7 días por sesión, ampliamente suficiente)
- **Payload:** Datos crudos del chunk WebM/Opus.
- **Acknowledgment:** El servidor responde con ACK incluyendo el `sequence_number` para confirmar recepción. Si no se recibe ACK en 5 segundos, el chunk se reintenta (máximo 3 reintentos con backoff exponencial).

Si la conexión WebSocket se pierde, los chunks se acumulan en el buffer local (limitado a 60 chunks / ~5 minutos de audio) y se envían al reconectarse, garantizando que no se pierde audio.

> **Nota sobre `timestamp_ms`:** El valor 0 corresponde al instante en que el cliente recibe el evento `recording:start`. Cada chunk posterior calcula su timestamp como `Date.now() - recordingStartTime`. Este diseño elimina la necesidad de sincronización de relojes entre clientes.

#### 6.1.3 Interfaz de Usuario

La interfaz se organiza en los siguientes elementos principales:

| Elemento | Descripción | Disponibilidad |
|----------|-------------|----------------|
| Panel de participantes | Avatares personalizados con alternancia idle/hablando según VAD e indicador de nivel de audio | Siempre visible |
| Botón Mutear/Desmutear | Toggle del micrófono local (afecta SFU y grabación) | Siempre visible |
| Botón Levantar Mano | Envía evento visual a todos los participantes | Siempre visible |
| Botón Marca de Tiempo | Crea bookmark con timestamp actual para referencia en edición | Durante grabación |
| Botón Sugerir Fin | Envía notificación al anfitrión sugiriendo cerrar la sesión | Durante grabación |
| Botón Prueba de Sonido | Graba 10 segundos y permite reproducir/descargar | Pre-grabación |
| Subida de Avatar | Formulario para subir imagen idle y hablando (PNG/GIF, max 2 MB c/u) | Pre-grabación |
| Botón Iniciar Grabación | Lanza cuenta regresiva e inicia grabación (solo anfitrión) | Pre-grabación (si no hay sesión activa) |
| Botón Finalizar Grabación | Lanza cuenta regresiva de cierre (solo anfitrión) | Durante grabación |
| Indicador de Estado | Muestra estado: conectando, en sala, grabando, procesando | Siempre visible |
| Cronómetro de Sesión | Tiempo transcurrido desde inicio de grabación | Durante grabación |
| Indicador de Sesiones | Número de sesión actual y estado de sesiones anteriores (solo si hay más de una) | Siempre visible (condicional) |
| Banner de Tiempo | Warning cuando se acerca el límite de grabación o de sala, con countdown en tiempo real | Condicional |

### 6.2 Servidor (Backend)

#### 6.2.1 API REST

| Endpoint | Método | Descripción | Auth |
|----------|--------|-------------|------|
| `/api/auth/register` | POST | Registrar nuevo usuario host (email + password) | No |
| `/api/auth/login` | POST | Iniciar sesión, retorna JWT de sesión larga + refresh token | No |
| `/api/auth/refresh` | POST | Renovar JWT usando refresh token | Refresh token |
| `/api/auth/me` | GET | Obtener perfil del usuario autenticado | JWT (host) |
| `/api/rooms` | POST | Crear nueva sala (asociada al usuario autenticado) | JWT (host) |
| `/api/rooms` | GET | Listar salas del usuario autenticado | JWT (host) |
| `/api/rooms/:code` | GET | Obtener info de sala por código de invitación | No |
| `/api/rooms/:id/join` | POST | Unirse a sala como guest (registra participante, retorna JWT efímero) | No (genera JWT efímero) |
| `/api/rooms/:id/settings` | GET | Obtener configuración de la sala | JWT (host) |
| `/api/rooms/:id/settings` | PATCH | Actualizar configuración de la sala | JWT (host) |
| `/api/rooms/:id/sessions` | GET | Listar sesiones de grabación de la sala | JWT (host o guest de la sala) |
| `/api/rooms/:id/recording/start` | POST | Iniciar grabación — valida sesión única activa y TTL restante | JWT (host) |
| `/api/rooms/:id/recording/stop` | POST | Finalizar grabación (solo anfitrión) | JWT (host) |
| `/api/rooms/:id/close` | POST | Cerrar sala manualmente | JWT (host) |
| `/api/rooms/:id/timestamps` | POST | Crear marca de tiempo | JWT (host o guest) |
| `/api/rooms/:id/timestamps` | GET | Listar marcas de tiempo de la sesión | JWT (host o guest) |
| `/api/sessions/:id/download` | GET | Obtener enlaces de descarga (post-procesamiento) | JWT (host o guest) |
| `/api/sessions/:id/processing-preset` | PUT | Configurar preset de procesamiento antes de procesar | JWT (host) |
| `/api/sound-check` | POST | Subir grabación de prueba de sonido | JWT (host o guest) |

**Notas sobre autenticación en endpoints:**
- Los endpoints de `auth` son públicos (registro y login).
- `POST /api/rooms` requiere JWT de host (usuario autenticado con cuenta persistente).
- `POST /api/rooms/:id/join` es público — el guest proporciona nombre y opcionalmente email, recibe un JWT efímero.
- Los endpoints dentro de una sala aceptan tanto JWT de host como JWT efímero de guest, validando pertenencia a la sala.
- Las acciones de control (iniciar/finalizar grabación, configurar sala, cerrar sala) requieren `role: host`.

#### 6.2.2 Eventos WebSocket

| Evento | Dirección | Descripción |
|--------|-----------|-------------|
| `room:join` | Cliente → Servidor | Participante se une a la sala (incluye JWT) |
| `room:leave` | Cliente → Servidor | Participante abandona la sala |
| `room:participant-joined` | Servidor → Clientes | Notifica nuevo participante |
| `room:participant-left` | Servidor → Clientes | Notifica salida de participante |
| `room:time-warning` | Servidor → Clientes | Warning 5 minutos antes de room TTL (todos los participantes) |
| `room:time-expired` | Servidor → Clientes | Room TTL expirado (todos los participantes) |
| `recording:countdown` | Servidor → Clientes | Cuenta regresiva de inicio/fin |
| `recording:start` | Servidor → Clientes | Orden de iniciar MediaRecorder |
| `recording:stop` | Servidor → Clientes | Orden de detener y enviar chunks restantes |
| `recording:time-warning` | Servidor → Host | Warning 5 minutos antes del límite de grabación |
| `recording:time-expired` | Servidor → Clientes | Límite de grabación alcanzado, stop automático |
| `chunk:data` | Cliente → Servidor | Envío de chunk de audio (binario) |
| `chunk:ack` | Servidor → Cliente | Confirmación de chunk recibido |
| `media:transport-connect` | Cliente ↔ Servidor | Negociación de mediasoup Transport |
| `media:produce` | Cliente → Servidor | Solicitar crear Producer en SFU |
| `media:consume` | Servidor → Cliente | Notificar nuevo Consumer disponible |
| `media:producer-closed` | Servidor → Clientes | Producer cerrado (participante salió/muteó) |
| `ui:hand-raise` | Cliente ↔ Todos | Levantar/bajar la mano |
| `ui:suggest-end` | Cliente → Anfitrión | Sugerir finalización de sesión |
| `ui:timestamp-mark` | Cliente → Servidor | Crear marca de tiempo |
| `vad:state` | Cliente → Servidor → Todos | Cambio de estado de voz (speaking/silent) para animar avatares |

#### 6.2.3 Gestión de Chunks en S3

Los chunks se almacenan en SeaweedFS con la siguiente estructura de claves:

```
sessions/{session_id}/participants/{participant_id}/chunks/{sequence_number}.webm
```

Adicionalmente se almacenan metadatos en PostgreSQL con la tabla `audio_chunks` que registra: `chunk_id`, `session_id`, `participant_id`, `sequence_number`, `timestamp_start_ms`, `timestamp_end_ms`, `s3_key`, `size_bytes`, `received_at`. Esto permite reconstruir la línea temporal completa de cada participante.

Toda interacción con SeaweedFS se realiza a través de la interfaz `StoragePort`:

```typescript
interface StoragePort {
  upload(key: string, data: Buffer, contentType: string): Promise<void>;
  download(key: string): Promise<Buffer>;
  getPresignedUrl(key: string, expiresIn: number): Promise<string>;
  delete(key: string): Promise<void>;
  deletePrefix(prefix: string): Promise<void>;
}
```

Esto permite sustituir SeaweedFS por otro proveedor S3-compatible en el futuro sin modificar la lógica de negocio.

#### 6.2.4 Límites y Backpressure en WebSocket

Para prevenir abuso y garantizar la estabilidad del servidor, se aplican los siguientes límites en las conexiones WebSocket:

| Parámetro | Valor | Comportamiento ante violación |
|-----------|-------|-------------------------------|
| Tamaño máximo de frame | 5 MB | Conexión cerrada con código 1009 (message too big) |
| Chunks/segundo por participante | Máximo 1 chunk cada 3 segundos | Chunks excedentes descartados con warning, 3 violaciones consecutivas → disconnect |
| Conexiones WebSocket por IP | Máximo 10 | Conexión rechazada con código 1008 (policy violation) |
| Mensajes de señalización/segundo | Máximo 20 | Mensajes excedentes ignorados, log de warning |
| Heartbeat interval | 30 segundos | Si el servidor no recibe heartbeat en 90s, marca participante como desconectado |

El servidor mantiene un contador por participante que se resetea cada segundo. Los eventos de violación se registran con structured logging para análisis posterior.

### 6.3 Procesamiento de Audio (Worker)

El worker de procesamiento es un servicio Python independiente que expone un endpoint REST para recibir solicitudes de procesamiento.

#### Arquitectura del Bridge BullMQ → Python

El flujo de comunicación es:

1. Cuando una sesión finaliza y se agota el periodo de gracia, NestJS encola un job en BullMQ con los metadatos de la sesión (`session_id`, `participant_ids`, `processing_preset`).
2. Un **consumer BullMQ** dentro de NestJS (no un servicio separado) dequeue el job.
3. El consumer envía una petición `POST /api/process` al worker Python con los metadatos.
4. El worker Python responde inmediatamente con `202 Accepted` y procesa en background.
5. El worker reporta progreso y resultado vía callbacks HTTP al endpoint `POST /api/internal/processing-status` de NestJS.

```
NestJS                          Python Worker
  │                                  │
  │── enqueue job (BullMQ) ─→        │
  │── dequeue job ──────────────→    │
  │                POST /api/process │
  │       ←── 202 Accepted ──────── │
  │                                  │── download chunks from SeaweedFS
  │                                  │── concatenate, silence, denoise
  │                                  │── upload results to SeaweedFS
  │  POST /internal/processing-status│
  │       ←────────────────────────  │
  │── update DB, send notifications  │
```

**Justificación de HTTP sobre otras alternativas:**
- **vs. subprocess:** HTTP permite escalar el worker independientemente, desplegarlo en otra máquina, y no comparte espacio de memoria con NestJS.
- **vs. Redis directo desde Python:** Acopla el worker a BullMQ/Dragonfly. Con HTTP, el worker es agnóstico al sistema de colas.
- **vs. gRPC:** Complejidad adicional innecesaria para este volumen de comunicación. HTTP es suficiente y más fácil de debuggear.

#### Tareas de Procesamiento

El worker ejecuta las siguientes tareas al recibir una solicitud:

1. **Descarga de chunks:** Descarga todos los chunks de SeaweedFS para cada participante de la sesión.
2. **Verificación de secuencia:** Ordena por `sequence_number` y detecta huecos (chunks faltantes por desconexión).
3. **Generación de silencio:** Para cada hueco detectado, genera un segmento de silencio con la duración correspondiente usando FFmpeg.
4. **Concatenación:** Une todos los chunks (incluyendo segmentos de silencio) en orden cronológico para producir la pista individual de cada participante.
5. **Reducción de ruido (según preset):** Si el preset de procesamiento lo indica, aplica filtro de reducción de ruido basado en RNNoise (`arnndn` en FFmpeg). Genera versión con y sin reducción de ruido; **nunca se descarta el audio original**.
6. **Normalización:** Aplica `loudnorm` de FFmpeg para normalizar el volumen a -16 LUFS (estándar para podcasts).
7. **Mezcla final:** Combina todas las pistas individuales en una pista consolidada usando FFmpeg `amix` filter.
8. **Exportación:** Genera archivos finales en el formato configurado (ver §6.8). Los sube a SeaweedFS y reporta resultado a NestJS vía HTTP callback.
9. **Notificación:** NestJS, al recibir el callback de éxito, envía notificaciones con enlaces de descarga temporales (presigned URLs con expiración de 72 horas). Si múltiples sesiones de la misma sala completan en un rango corto (< 5 minutos), las notificaciones se agrupan en un solo email para evitar spam.

### 6.4 Manejo de Desconexiones, Reconexiones y Límites de Tiempo

Este es uno de los aspectos más críticos del sistema. El diseño contempla múltiples escenarios de desconexión y la interacción con los límites de tiempo configurables.

#### 6.4.1 Escenarios de Desconexión

**Escenario 1 — Desconexión breve (< 30s):** El cliente detecta la caída del WebSocket e intenta reconectar automáticamente con backoff exponencial (1s, 2s, 4s, 8s, max 30s). Los chunks se acumulan en el buffer local. Al reconectar, se re-autentica con su JWT (ver §7), envía todos los chunks pendientes con sus timestamps originales, y restablece su conexión al SFU (mediasoup reconecta el Transport). El servidor los procesa normalmente.

**Escenario 2 — Desconexión prolongada (> 30s, < duración sesión):** Además del comportamiento anterior, el servidor marca al participante como "desconectado" y notifica a los demás vía WebSocket. Si el participante vuelve, re-autentica, se restablece la conexión al SFU con los Producers/Consumers correspondientes. Los chunks acumulados se envían y los huecos se cubrirán con silencio en post-procesamiento.

**Escenario 3 — Participante no regresa:** Si la sesión termina y un participante no se reconectó, el servidor espera el periodo de gracia configurado (**por defecto 5 minutos**, configurable en `room_settings`). Transcurrido ese tiempo, el worker genera silencio desde el último chunk recibido hasta el final de la sesión, produciendo una pista completa con la misma duración que las demás.

**Escenario 4 — Pérdida total del dispositivo:** En el peor caso, si el cliente pierde el dispositivo y no puede enviar chunks pendientes, la pista del participante contendrá audio hasta el último chunk recibido por el servidor, complementado con silencio. Los chunks perdidos se marcan como irrecuperables en los metadatos.

#### 6.4.2 Límites de Tiempo y Enforcement

Los límites de tiempo se configuran en `room_settings` y se hacen cumplir exclusivamente en el servidor mediante delayed jobs en BullMQ:

**Room TTL (`max_room_duration_ms`):** Se programa un delayed job al crear la sala con delay igual al valor configurado. El job ID se almacena en `rooms.ttl_job_id` para poder cancelarlo si el host cierra la sala antes. Default: 7200000 (2 horas). Mínimo: 60000 (1 minuto). `null` = sin límite. Hard limit global: variable de entorno `MAX_ROOM_DURATION_HARD_LIMIT`.

**Recording Limit (`max_recording_duration_ms`):** Se programa un delayed job al iniciar cada grabación con delay igual al valor configurado. El job ID se almacena en `recording_sessions.limit_job_id` para cancelarlo si el host detiene la grabación manualmente. Default: 3600000 (1 hora). Mínimo: 60000 (1 minuto). `null` = sin límite. Hard limit global: variable de entorno `MAX_RECORDING_DURATION_HARD_LIMIT`.

**Validación al iniciar grabación:** Antes de permitir iniciar una nueva sesión de grabación, el servidor valida que el TTL restante de la sala es mayor al umbral mínimo (5 minutos). Calcula `remaining_ttl = max_room_duration_ms - (Date.now() - room.created_at)`. Retorna error 403 si el TTL restante es insuficiente.

#### 6.4.3 Room TTL con Grabación Activa

Si el Room TTL expira durante una grabación activa o un grace period, el sistema NO corta abruptamente. El flujo es:

1. Emitir `room:time-expired` a todos los participantes.
2. Si hay sesión en `recording`: emitir `recording:time-expired`, luego ejecutar stop normal (countdown → stop → grace period).
3. Si hay sesión en `grace_period`: esperar a que complete.
4. Encolar procesamiento.
5. Cerrar sala.

El TTL efectivo máximo es `max_room_duration_ms + countdown_duration + grace_period_ms`. Esto prioriza la integridad de los datos sobre la exactitud del límite.

#### 6.4.4 Reconexión e Interacción con Límites

Cuando un participante se reconecta en un contexto de expiración de límites:

- Si la sala ya está `closed`: recibe error claro "Sala cerrada" en la reconexión.
- Si se reconecta durante un countdown de forzado por TTL: recibe el estado actual (countdown en progreso) y puede enviar chunks pendientes.
- Si se reconecta durante grace period de una sesión forzada: puede enviar chunks pendientes normalmente.

#### 6.4.5 Recovery de Delayed Jobs tras Restart

Al iniciar NestJS, el servicio consulta todas las salas `active` con `ttl_job_id` no null y todas las sesiones en `recording` o `grace_period` con `limit_job_id` no null. Para cada una, verifica si el job existe en BullMQ. Si no existe (perdido por restart), calcula el delay restante y reprograma el job. Si el TTL ya expiró durante el downtime, ejecuta la acción de cierre inmediatamente. El recovery se registra con log `info` indicando la cantidad de jobs reprogramados.

### 6.5 Reducción de Ruido

La reducción de ruido se implementa en dos niveles opcionales:

**Nivel 1 — Cliente (tiempo real, opcional):** RNNoise compilado a WebAssembly se ejecuta como un AudioWorklet en el navegador. Procesa el audio del micrófono antes de enviarlo al SFU (mejorando la experiencia en vivo) pero **NO afecta la grabación local**, que se mantiene con audio crudo para preservar la máxima calidad. Este nivel es opcional y se activa por configuración del usuario. Su consumo es mínimo (~2-3% CPU adicional).

**Nivel 2 — Servidor (post-procesamiento):** Durante el procesamiento del worker, si el preset de procesamiento lo indica, se aplica el filtro `arnndn` de FFmpeg sobre las pistas concatenadas. Esto **siempre genera dos versiones** de cada pista: una cruda (original) y una con reducción de ruido, para que el editor pueda elegir cuál usar. El audio original nunca se destruye.

### 6.6 Modelo de Datos

| Tabla | Campos Principales | Propósito |
|-------|-------------------|-----------|
| `users` | `id (UUID PK)`, `email (unique)`, `password_hash`, `created_at` | Cuentas persistentes de hosts |
| `rooms` | `id (UUID PK)`, `code (unique)`, `status (enum: active/closed)`, `owner_user_id (UUID FK → users, nullable)`, `ttl_job_id (VARCHAR nullable)`, `created_at` | Salas de podcast |
| `room_settings` | `id`, `room_id (FK unique)`, `chunk_interval_ms (default 5000)`, `grace_period_ms (default 300000)`, `max_participants (default 5)`, `export_format (enum: flac/wav/mp3, default flac)`, `max_room_duration_ms (INT nullable, default 7200000)`, `max_recording_duration_ms (INT nullable, default 3600000)` | Configuración de cada sala |
| `participants` | `id (UUID PK)`, `room_id (FK)`, `user_id (UUID nullable)`, `display_name`, `email (nullable)`, `role (enum: host/guest)`, `status (enum: connected/disconnected/left)`, `joined_at` | Participantes de cada sala |
| `participant_avatars` | `id`, `participant_id (FK)`, `idle_image_s3_key`, `speaking_image_s3_key` | Imágenes de avatar idle/hablando |
| `recording_sessions` | `id (UUID PK)`, `room_id (FK)`, `started_at`, `ended_at`, `status (enum: recording/grace_period/processing/completed/failed)`, `limit_job_id (VARCHAR nullable)` | Sesiones de grabación (múltiples por sala) |
| `processing_presets` | `id`, `session_id (FK unique)`, `noise_reduction (boolean, default false)`, `normalize_lufs (decimal, default -16)`, `export_format (enum: flac/wav/mp3, nullable → hereda de room_settings)` | Configuración de procesamiento por sesión, editable por el host antes de procesar |
| `audio_chunks` | `id`, `session_id (FK)`, `participant_id (FK)`, `seq_num`, `ts_start_ms`, `ts_end_ms`, `s3_key`, `size_bytes`, `status (enum: received/processing/irrecoverable)`, `received_at` | Registro de cada chunk subido |
| `vad_events` | `id`, `session_id (FK)`, `participant_id (FK)`, `state (enum: speaking/silent)`, `ts_ms` | Eventos de inicio/fin de voz (VAD) |
| `timestamp_marks` | `id`, `session_id (FK)`, `participant_id (FK)`, `ts_ms`, `label (nullable)` | Marcas de tiempo creadas por usuarios |
| `processed_tracks` | `id`, `session_id (FK)`, `participant_id (FK nullable — null para mezcla)`, `format (enum: flac/wav/mp3)`, `variant (enum: raw/denoised/mix)`, `s3_key`, `duration_ms` | Pistas procesadas finales |
| `notifications` | `id`, `session_id (FK)`, `participant_id (FK)`, `type (enum: email/webhook)`, `sent_at`, `download_url` | Notificaciones de descarga |

**Notas sobre el modelo de datos:**

- **`users`:** Tabla mínima para el MVP. Solo contiene campos de autenticación. En iteraciones futuras se extiende con `plan_id (FK → plans)`, preferencias de perfil, y OAuth tokens.
- **`rooms.owner_user_id`:** FK a `users`. Nullable para permitir desarrollo local sin autenticación activada (el `AuthModule` puede desactivarse con una variable de entorno para desarrollo). En producción, siempre se popula con el `user_id` del host autenticado al crear la sala.
- **`rooms.status`:** Simplificado a dos valores: `active` (sala abierta, participantes pueden unirse/salir, se pueden iniciar/finalizar grabaciones) y `closed` (estado terminal). Los estados de grabación (`recording`, `grace_period`, `processing`, etc.) pertenecen al ciclo de vida de `recording_sessions`, no de la sala.
- **`participants.user_id`:** Nullable. Para hosts autenticados, se popula con su `user_id` de la tabla `users`. Para guests efímeros, permanece `null`. Actúa como puente de vinculación retroactiva: si un guest crea cuenta en el futuro, se pueden asociar sus participaciones anteriores mediante `participants.email`.
- **`participants.email`:** Se captura en `POST /api/rooms` y `POST /api/rooms/:id/join` siempre que el participante lo proporcione. No es obligatorio pero su presencia habilita notificaciones y vinculación futura.
- **Resolución de circularidad host:** El host se identifica mediante el campo `role: host` en `participants` y la relación `rooms.owner_user_id → users.id`. No existe referencia circular.
- **`recording_sessions`:** Múltiples por sala (relación `rooms` 1:N `recording_sessions`). Solo una sesión puede estar en estado `recording` o `grace_period` a la vez por sala.
- **`processing_presets`:** Permite al host configurar las opciones de procesamiento *después* de finalizar la grabación pero *antes* de que el worker procese el audio. Si no se crea un preset explícito, se heredan los valores por defecto y la configuración de `room_settings`. El audio original siempre se conserva en SeaweedFS como los chunks crudos.
- **`rooms.ttl_job_id` y `recording_sessions.limit_job_id`:** Almacenan el ID del delayed job de BullMQ para poder cancelarlo si el host cierra la sala o detiene la grabación manualmente, y para reprogramarlos tras un restart del servidor.

### 6.7 Detección de Voz y Sistema de Avatares

El sistema de avatares animados permite a cada participante subir dos imágenes (idle y hablando) que se alternan automáticamente según la detección de actividad de voz (VAD). Esta funcionalidad tiene doble propósito: mejorar la experiencia visual en vivo durante la sesión y generar datos para la producción de video en post-procesamiento.

#### 6.7.1 Voice Activity Detection (VAD)

La detección de voz se implementa en el cliente usando la Web Audio API nativa del navegador. Se crea un `AnalyserNode` conectado al stream del micrófono que calcula el nivel RMS (Root Mean Square) del audio cada 50-100 milisegundos. El algoritmo compara este nivel contra un umbral configurable para determinar si el participante está hablando o en silencio.

Para evitar parpadeos rápidos entre estados (speaking/silent), se aplica un **hold time** de 300-500 milisegundos: una vez que se detecta voz, el estado se mantiene como "hablando" durante ese periodo mínimo antes de volver a "silencio". Opcionalmente, la detección se limita al rango de frecuencias de la voz humana (85 Hz - 3000 Hz) para reducir falsos positivos por ruido ambiental.

El consumo de recursos de esta detección es despreciable (< 1% CPU) ya que utiliza la API nativa del navegador sin librerías externas.

#### 6.7.2 Sistema de Avatares

Antes de iniciar la grabación, cada participante puede subir dos imágenes:

- **Imagen idle:** Se muestra cuando el participante no está hablando. Representa al personaje o avatar en estado de reposo.
- **Imagen hablando:** Se muestra cuando el VAD detecta actividad de voz. Representa al personaje con la boca abierta o en actitud de hablar.

Las imágenes se almacenan en SeaweedFS asociadas al participante (tabla `participant_avatars`). Se aceptan formatos PNG y GIF con un tamaño máximo de 2 MB por imagen. Si un participante no sube imágenes, se muestra un avatar genérico con la inicial de su nombre y un indicador de borde iluminado como feedback visual alternativo.

La alternancia entre imágenes se realiza con una transición CSS crossfade suave (150ms) para evitar un corte visual abrupto. El estado de VAD de cada participante se distribuye a todos los clientes de la sala vía el evento WebSocket `vad:state`, de manera que todos ven la animación del avatar correspondiente en tiempo real.

#### 6.7.3 Registro de Eventos VAD para Post-Producción

Durante la grabación, cada cambio de estado de voz se registra en la tabla `vad_events` con el timestamp exacto (en milisegundos relativos al inicio de la sesión de grabación). Cada registro contiene: `participant_id`, `state` (speaking/silent), y `ts_ms`.

Los eventos VAD se exportan como un archivo JSON con el siguiente schema:

```json
{
  "version": "1.0",
  "session_id": "uuid",
  "recording_started_at": "ISO-8601",
  "duration_ms": 3600000,
  "participants": [
    {
      "id": "uuid",
      "display_name": "string",
      "events": [
        { "state": "speaking", "ts_ms": 1200 },
        { "state": "silent", "ts_ms": 4500 },
        { "state": "speaking", "ts_ms": 8200 }
      ]
    }
  ]
}
```

Los eventos VAD tienen múltiples usos en post-producción:

- **Generación de video:** Reconstruir la animación de avatares para producir un video del episodio sin necesidad de cámaras.
- **Mapa de actividad:** Visualizar quién habló y cuánto en una línea temporal, útil para el editor.
- **Detección de crosstalk:** Identificar momentos donde dos o más personas hablaron simultáneamente para revisión en edición.
- **Exportación como metadato:** Los eventos se incluyen como archivo JSON junto con las pistas de audio descargables.

### 6.8 Formatos de Exportación

El sistema soporta múltiples formatos de exportación, configurables a nivel de sala (`room_settings.export_format`) y sobreescribibles a nivel de sesión (`processing_presets.export_format`):

| Formato | Codec | Calidad | Tamaño (1h mono) | Caso de uso |
|---------|-------|---------|-------------------|-------------|
| **FLAC** (default) | FLAC | Lossless | ~200-300 MB | Edición profesional. Compresión ~50-60% vs WAV sin pérdida de calidad. Compatible con Audacity, Reaper, Logic, Adobe Audition |
| WAV | PCM 16-bit | Lossless | ~635 MB | Máxima compatibilidad con DAWs legacy |
| MP3 | LAME 320kbps | Lossy (alta calidad) | ~150 MB | Revisión rápida, distribución |

**Regla:** El worker siempre genera la pista en el formato configurado. Adicionalmente, siempre genera una versión MP3 para preview/revisión rápida, independientemente del formato principal seleccionado.

**Nota:** Los chunks crudos en SeaweedFS (WebM/Opus) nunca se eliminan hasta que el host lo solicite explícitamente o hasta que expire la política de retención configurada. Esto permite reprocesar las pistas con diferentes configuraciones en cualquier momento.

---

## 7. Flujo de Identidad y Autenticación

### 7.1 Principios

PodSync implementa un modelo de **identidad asimétrica** entre hosts y guests:

| | Host | Guest |
|---|---|---|
| **MVP** | Cuenta persistente obligatoria (email + password) | JWT efímero, sin cuenta |
| **Futuro** | Cuenta con OAuth opcional, vinculada a plan comercial | Sigue efímero por defecto; cuenta opcional para precargar perfil |

Esta asimetría refleja una diferencia estructural del producto: el host es el propietario del contenido (grabaciones, configuraciones, historial), mientras que el guest es un participante ocasional que no necesita persistencia.

### 7.2 Autenticación del Host

#### Registro

```
Cliente                          Servidor
  │                                  │
  │── POST /api/auth/register ──→    │
  │   { email, password }            │
  │                                  │── Valida email único
  │                                  │── Hash password con argon2
  │                                  │── Crea user en DB
  │                                  │── Genera JWT + refresh token
  │       ←── 201 Created ────────── │
  │   { user_id, jwt, refresh_token }│
```

#### Login

```
Cliente                          Servidor
  │                                  │
  │── POST /api/auth/login ───────→  │
  │   { email, password }            │
  │                                  │── Busca user por email
  │                                  │── Verifica password con argon2
  │                                  │── Genera JWT + refresh token
  │       ←── 200 OK ────────────── │
  │   { user_id, jwt, refresh_token }│
```

#### JWT del Host

```json
{
  "sub": "<user_id (UUID)>",
  "email": "host@example.com",
  "type": "host",
  "iat": 1712000000,
  "exp": 1712604800
}
```

- **Algoritmo:** HS256 con secreto almacenado en variable de entorno (`JWT_SECRET`).
- **Expiración:** 7 días.
- **Refresh token:** Token opaco almacenado en base de datos con expiración de 30 días. Permite renovar el JWT sin re-login. Se invalida al hacer logout o al cambiar la contraseña.

#### Almacenamiento en Cliente (Host)

El JWT del host se almacena en memoria (React state/context). El refresh token se almacena en una cookie `httpOnly`, `secure`, `sameSite: strict` para máxima seguridad. Esto previene acceso desde JavaScript (protección contra XSS) mientras permite renovación automática del JWT.

### 7.3 Identidad del Guest (Efímera)

El flujo del guest no cambia respecto a versiones anteriores del TDD:

#### Unirse a sala

```
Cliente                          Servidor
  │                                  │
  │── POST /api/rooms/:id/join ──→   │
  │   { display_name, email? }       │
  │                                  │── Crea participant (role: guest, user_id: null)
  │                                  │── Genera JWT efímero
  │       ←── 200 OK ────────────── │
  │   { jwt, participant_id }       │
```

#### JWT del Guest

```json
{
  "sub": "<participant_id (UUID)>",
  "room_id": "<room_id (UUID)>",
  "role": "guest",
  "display_name": "string",
  "type": "guest",
  "iat": 1712000000,
  "exp": 1712086400
}
```

- **Expiración:** 24 horas. Una sesión de grabación típica dura 1-3 horas; 24h da margen amplio para reconexiones y descarga.
- **Sin refresh token:** Si el JWT expira, el guest debe volver a unirse a la sala (se crea un nuevo `participant_id`).

#### Almacenamiento en Cliente (Guest)

El JWT del guest se almacena en **memoria** (variable JavaScript). No se usa `localStorage` ni `sessionStorage` para evitar que el token persista si la pestaña se cierra y se reabre manualmente.

**Excepción para reconexión automática:** Durante una sesión de grabación activa, el JWT se almacena temporalmente en `sessionStorage` para permitir reconexión automática tras un refresh accidental del navegador. Se elimina de `sessionStorage` cuando la sesión de grabación finaliza o la sala se cierra.

### 7.4 Creación de Sala (Host Autenticado)

```
Cliente                          Servidor
  │                                  │
  │── POST /api/rooms ───────────→   │
  │   Authorization: Bearer <jwt>    │
  │   { }                           │
  │                                  │── Valida JWT de host
  │                                  │── Crea room (owner_user_id = jwt.sub)
  │                                  │── Crea participant (role: host, user_id = jwt.sub)
  │                                  │── Programa Room TTL delayed job (si configurado)
  │       ←── 201 Created ────────── │
  │   { room_id, code,              │
  │     participant_id }             │
```

**Nota:** El host no necesita un JWT efímero separado para participar en la sala. Su JWT de sesión larga (7 días) se usa tanto para la API REST como para el WebSocket. El servidor identifica al host tanto por su `user_id` como por su `role: host` en `participants`.

### 7.5 Uso del Token

| Contexto | Host | Guest |
|----------|------|-------|
| API REST | Header `Authorization: Bearer <jwt>` (JWT de 7 días) | Header `Authorization: Bearer <jwt>` (JWT efímero de 24h) |
| WebSocket | Enviado en el evento `room:join` como campo `token`. Validado en el Gateway Guard | Mismo mecanismo |
| mediasoup | La conexión al SFU se establece solo después de autenticación exitosa en WebSocket. No requiere auth adicional | Mismo mecanismo |

### 7.6 Autorización por Rol

| Acción | Host | Guest |
|--------|------|-------|
| Registrar cuenta | ✅ | — |
| Login | ✅ | — |
| Crear sala | ✅ (requiere auth) | ❌ |
| Listar sus salas | ✅ | — |
| Unirse a sala | — | ✅ (sin auth, con código) |
| Iniciar/finalizar grabación | ✅ | ❌ |
| Configurar sala (settings) | ✅ | ❌ |
| Configurar preset de procesamiento | ✅ | ❌ |
| Cerrar sala | ✅ | ❌ |
| Mutear/desmutear propio | ✅ | ✅ |
| Levantar la mano | ✅ | ✅ |
| Crear marca de tiempo | ✅ | ✅ |
| Sugerir finalización | ❌ | ✅ |
| Subir avatar | ✅ | ✅ |
| Descargar pistas procesadas | ✅ | ✅ |
| Prueba de sonido | ✅ | ✅ |
| Listar sesiones de la sala | ✅ | ✅ |

### 7.7 Guard de Autorización del Host

El Guard de NestJS que verifica si un participante es host se implementa de forma que su lógica interna sea reemplazable sin afectar a los controllers que lo consumen:

```typescript
@Injectable()
export class HostGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const jwt = extractJwt(context);

    if (jwt.type === 'host') {
      // Host autenticado: validar user_id contra rooms.owner_user_id
      const roomId = extractRoomId(context);
      return this.roomsService.isOwner(jwt.sub, roomId);
    }

    // Guest JWT: validar role en participants
    return jwt.role === 'host'; // siempre false para guests
  }
}
```

Esta encapsulación garantiza que la lógica de autorización tiene un único punto de cambio. En el futuro, cuando se introduzcan planes comerciales, este Guard puede extenderse para verificar también si el plan del usuario permite la acción solicitada.

### 7.8 Reconexión y Re-autenticación

**Host:** Al reconectar, envía su JWT de sesión larga en `room:join`. El servidor valida el JWT y verifica que el `user_id` corresponde al `owner_user_id` de la sala. Si el JWT expiró, el host puede renovarlo con el refresh token (cookie `httpOnly`) sin necesidad de re-login.

**Guest:** Al reconectar durante una sesión activa, envía el JWT efímero almacenado en `sessionStorage`. El servidor valida el JWT y verifica que el `participant_id` del token corresponde a un participante existente en la sala con status `disconnected`. Si el JWT ha expirado, el guest debe re-unirse como nuevo participante.

### 7.9 Modo de Desarrollo sin Autenticación

Para facilitar el desarrollo local, el `AuthModule` puede desactivarse mediante la variable de entorno `AUTH_ENABLED=false`. En este modo:

- `POST /api/rooms` no requiere JWT — crea la sala con `owner_user_id = null`.
- Todos los Guards de host validan basándose en `jwt.role === 'host'` del JWT efímero (comportamiento del TDD v1.5).
- Se muestra un warning en el log al iniciar: `"⚠️ Auth disabled — development mode only"`.

Este modo NO debe usarse en producción. La variable `AUTH_ENABLED` tiene default `true`.

---

## 8. Consideraciones de Seguridad

- **Autenticación de hosts:** Registro con email + contraseña hasheada con argon2 (parámetros: `memoryCost: 65536`, `timeCost: 3`, `parallelism: 4`). Rate limiting en login: máximo 10 intentos por email en 15 minutos, con lockout temporal de 30 minutos.
- **Salas con código único:** Códigos de 8 caracteres alfanuméricos generados con `crypto.randomBytes`, lo que da ~2.8 trillones de combinaciones.
- **JWT diferenciados:** JWT de sesión larga para hosts (7 días + refresh token en cookie httpOnly), JWT efímeros para guests (24 horas, sin refresh). Ver §7 para detalles completos.
- **HTTPS/WSS obligatorio:** Todo el tráfico está cifrado en tránsito. mediasoup usa DTLS/SRTP por defecto para el transporte de media.
- **URLs de descarga temporales:** Presigned URLs de SeaweedFS con expiración de 72 horas para proteger el contenido.
- **Rate limiting:** Límites en creación de salas (5/hora por usuario autenticado), intentos de login (10/15 min por email), registro (3/hora por IP), conexiones WebSocket por IP (10 simultáneas), y backpressure en envío de chunks (ver §6.2.4).
- **Validación de chunks:** Verificación de tamaño máximo por chunk (5 MB) y formato válido para prevenir carga de datos maliciosos.
- **Hard limits globales:** Variables de entorno `MAX_ROOM_DURATION_HARD_LIMIT` y `MAX_RECORDING_DURATION_HARD_LIMIT` que actúan como techo absoluto para los valores de `room_settings`, impidiendo que un host configure valores arbitrariamente altos. En el futuro, estos hard limits se reemplazan por los topes del plan comercial del usuario.
- **Secretos:** `JWT_SECRET`, `REFRESH_TOKEN_SECRET`, y credenciales de SeaweedFS se gestionan mediante variables de entorno, nunca en código fuente ni en Docker Compose de producción.
- **CORS:** Configurado para aceptar únicamente el origen del frontend (`ALLOWED_ORIGIN` env var).
- **Protección contra brute force:** Además del rate limiting en login, se implementa un delay incremental en respuestas fallidas para dificultar ataques automatizados.

---

## 9. Estrategia de Testing

### 9.1 Niveles de Testing

| Nivel | Herramientas | Alcance | Responsable |
|-------|-------------|---------|-------------|
| **Unit Tests** | Jest (NestJS), pytest (Python worker) | Services, Guards, utils, protocol parsing, chunk validation, processing pipeline, auth logic | Desarrollador en cada PR |
| **Integration Tests** | Jest + Supertest (NestJS), testcontainers (PostgreSQL, Dragonfly) | WebSocket flows completos, API REST, autenticación, interacción con base de datos y SeaweedFS | CI en cada PR |
| **E2E Tests** | Playwright (multi-tab) | Flujos completos de usuario: registrar, crear sala, unirse, grabar, descargar | CI en merge a main |
| **Load/Stress Tests** | k6 o Artillery | Validar RNF-01 (CPU/RAM), RNF-07 (salas concurrentes), backpressure WebSocket | Pre-release (Hito 6-7) |

### 9.2 Escenarios Críticos de Testing

Los siguientes escenarios deben tener cobertura explícita por su complejidad y riesgo:

- **Autenticación:** Registro exitoso, login exitoso, login fallido (credenciales incorrectas, lockout por rate limit), refresh token, acceso a endpoints protegidos sin JWT, acceso con JWT expirado.
- **Asimetría host/guest:** Guest intenta crear sala → rechazado. Guest intenta iniciar grabación → rechazado. Host accede a sala ajena → rechazado.
- **Desconexión durante grabación:** Simular pérdida de WebSocket a mitad de sesión, verificar que chunks se acumulan y re-envían tras reconexión.
- **Desconexión múltiple simultánea:** Dos participantes se desconectan al mismo tiempo, verificar que el servidor maneja ambos correctamente.
- **Buffer overflow en cliente:** Llenar buffer a 60 chunks sin conexión, verificar comportamiento (¿descarta los más antiguos? ¿detiene grabación?).
- **Chunks fuera de orden:** Enviar chunks con `sequence_number` desordenado, verificar que el worker los reordena correctamente.
- **Periodo de gracia:** Verificar que chunks recibidos durante el grace period se incorporan correctamente.
- **Protocolo binario:** Validar parsing del header de 40 bytes con edge cases (valores máximos, UUIDs con bytes especiales).
- **mediasoup Transport:** Verificar reconexión de Producer/Consumer tras disconnect/reconnect.
- **Procesamiento con huecos:** Worker recibe sesión con chunks faltantes (gaps), verificar generación correcta de silencio y alineación temporal.
- **Cross-browser:** Validar MediaRecorder + Web Audio API + mediasoup-client en Chrome, Firefox, Edge, Safari.
- **Múltiples sesiones por sala:** Crear sala → grabar sesión 1 → detener → iniciar sesión 2 → detener → ambas procesan correctamente con chunks separados.
- **Sesión activa única:** Dos requests simultáneas de `recording/start` → solo una tiene éxito (409 Conflict).
- **Room TTL con grabación activa:** TTL expira con grabación activa → sesión pasa por todos los estados → sala cerrada.
- **Recording Limit:** Grabación alcanza el límite → stop automático con countdown.
- **Recovery de delayed jobs:** Crear sala con TTL → matar proceso NestJS → reiniciar → sala se cierra al expirar el TTL reprogramado.
- **Reconexión durante expiración:** Participante se reconecta justo cuando recording limit o room TTL expira.

### 9.3 Cobertura Mínima

- **Unit tests:** ≥ 80% de cobertura en services y utils.
- **Integration tests:** 100% de endpoints REST y eventos WebSocket del flujo crítico (registrar → crear sala → grabar → procesar → descargar).
- **E2E tests:** Al menos 3 flujos completos (happy path, reconexión, 5 participantes).

---

## 10. Observabilidad y Monitorización

### 10.1 Structured Logging

Toda la aplicación utiliza **pino** como logger en NestJS, configurado para output JSON en producción. Cada log entry incluye como mínimo:

- `timestamp` (ISO 8601)
- `level` (trace/debug/info/warn/error/fatal)
- `service` (api, ws-gateway, chunk-receiver, media, worker, auth)
- `request_id` o `session_id` (para correlación)
- `participant_id` (cuando aplica)
- `user_id` (cuando aplica, para operaciones de host)

Categorías de log críticas:

| Evento | Nivel | Campos adicionales |
|--------|-------|--------------------|
| Registro de usuario | `info` | `user_id`, `email` (redactado) |
| Login exitoso | `info` | `user_id` |
| Login fallido | `warn` | `email` (redactado), `reason`, `attempt_count` |
| Login lockout | `warn` | `email` (redactado), `lockout_until` |
| Chunk recibido | `info` | `session_id`, `participant_id`, `seq_num`, `size_bytes`, `latency_ms` |
| Chunk ACK enviado | `debug` | `session_id`, `seq_num` |
| Participante desconectado | `warn` | `session_id`, `participant_id`, `last_seq_num`, `buffer_pending` |
| Participante reconectado | `info` | `session_id`, `participant_id`, `chunks_pending`, `disconnect_duration_ms` |
| Backpressure violation | `warn` | `participant_id`, `violation_type`, `count` |
| Room TTL warning | `info` | `room_id`, `remaining_ms` |
| Room TTL expired | `info` | `room_id`, `had_active_session` |
| Recording limit expired | `info` | `session_id`, `duration_ms` |
| Delayed job recovery | `info` | `jobs_reprogrammed`, `jobs_expired` |
| Procesamiento iniciado | `info` | `session_id`, `participant_count`, `total_chunks` |
| Procesamiento completado | `info` | `session_id`, `duration_ms`, `output_format`, `output_size_bytes` |
| Procesamiento fallido | `error` | `session_id`, `error_message`, `stack` |
| Auth disabled warning | `warn` | (emitido al iniciar si `AUTH_ENABLED=false`) |

### 10.2 Métricas

Métricas expuestas vía endpoint `/metrics` (formato Prometheus-compatible):

| Métrica | Tipo | Descripción |
|---------|------|-------------|
| `podsync_active_rooms` | Gauge | Salas activas actualmente |
| `podsync_active_participants` | Gauge | Participantes conectados |
| `podsync_registered_users_total` | Counter | Total de usuarios registrados |
| `podsync_auth_login_total` | Counter | Total de intentos de login (label: success/failure) |
| `podsync_chunks_received_total` | Counter | Total de chunks recibidos |
| `podsync_chunks_bytes_total` | Counter | Bytes totales de chunks recibidos |
| `podsync_chunk_latency_ms` | Histogram | Latencia entre generación y recepción de chunk |
| `podsync_ws_connections_total` | Counter | Total de conexiones WebSocket (acumulado) |
| `podsync_ws_disconnections_total` | Counter | Total de desconexiones |
| `podsync_processing_duration_ms` | Histogram | Duración de procesamiento por sesión |
| `podsync_processing_queue_size` | Gauge | Jobs pendientes en BullMQ |
| `podsync_mediasoup_transports_active` | Gauge | Transports activos en mediasoup |
| `podsync_room_ttl_expirations_total` | Counter | Total de salas cerradas por TTL |
| `podsync_recording_limit_expirations_total` | Counter | Total de grabaciones detenidas por límite |

### 10.3 Health Checks

| Endpoint | Verifica |
|----------|----------|
| `GET /health` | API NestJS respondiendo |
| `GET /health/ready` | PostgreSQL + Dragonfly + SeaweedFS conectados, mediasoup worker activo |
| `GET /health/worker` (Python) | Worker Python respondiendo y con acceso a SeaweedFS |

### 10.4 Alertas Recomendadas

- `podsync_processing_queue_size > 10` durante > 5 minutos → Worker saturado.
- `podsync_ws_disconnections_total` spike > 50% en 1 minuto → Posible problema de red.
- Health check fallido durante > 30 segundos → Servicio caído.
- Tasa de error HTTP 5xx > 1% → Problema en API.
- `podsync_auth_login_total{result="failure"}` spike → Posible ataque de fuerza bruta.

---

## 11. Plan de Desarrollo por Hitos

El desarrollo se organiza en iteraciones incrementales. Cada hito produce un entregable funcional que se puede probar con usuarios reales. Las estimaciones asumen un desarrollador individual.

### 11.1 Hito 1 — Infraestructura, Autenticación y Comunicación Básica

**Duración estimada:** 5-6 semanas

**Objetivo:** Establecer la base técnica del proyecto con autenticación para hosts, comunicación en tiempo real funcional vía SFU, y estructura del monorepo.

- Setup del monorepo con Turborepo + pnpm workspaces (frontend React + backend NestJS con Fastify adapter).
- Docker Compose con PostgreSQL, Dragonfly, SeaweedFS y mediasoup.
- Esquema Prisma inicial: `users`, `rooms`, `participants`, `room_settings` (con campos de límites de tiempo), `recording_sessions`.
- `rooms.status` con enum simplificado: `active` / `closed`.
- Tabla `users` con campos mínimos: `id`, `email`, `password_hash`, `created_at`.
- `rooms.owner_user_id` con FK a `users` (nullable para modo desarrollo).
- `participants.user_id` nullable.
- `AuthModule` con Passport.js: `LocalStrategy` (email + argon2), `JwtStrategy`.
- Endpoints de auth: `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `GET /auth/me`.
- Variable de entorno `AUTH_ENABLED` para desactivar auth en desarrollo local.
- `HostGuard` encapsulado con lógica reemplazable.
- API REST: crear sala (autenticado), unirse a sala (público para guests), obtener info de sala, listar salas del host.
- NestJS WebSocket Gateway con gestión básica de salas (crear, unirse, salir) con autenticación JWT (diferenciando host y guest).
- Integración de mediasoup: Router, WebRtcTransport, Producer/Consumer por participante.
- Comunicación de voz entre 2+ participantes vía SFU.
- Interfaz mínima: pantalla de registro/login, crear/unirse a sala + panel de participantes.
- Botón de muteo/desmuteo funcional.
- Interfaz `StoragePort` con implementación SeaweedFS.
- Seed de desarrollo: comando `pnpm seed:admin` para crear usuario de prueba.

**Entregable:** Usuarios host pueden registrarse, crear sala con identidad, compartir enlace, guests se unen con nombre/email sin registro, y todos hablan en tiempo real vía SFU.

### 11.2 Hito 2 — Grabación Local y Envío de Chunks (MVP)

**Duración estimada:** 5-6 semanas

**Objetivo:** Core del producto — grabación individual con envío al servidor, múltiples sesiones por sala, y enforcement de límites de tiempo.

- Implementar MediaRecorder con timeslice configurable (5-10 segundos).
- Web Worker para buffer y envío de chunks por WebSocket binario con header de 40 bytes.
- Servidor: recepción de chunks con validación de `session_id` (no mezclar chunks entre sesiones), backpressure (§6.2.4), metadatos en PostgreSQL, almacenamiento en SeaweedFS.
- Protocolo de ACK para confirmación de recepción de chunks.
- Validación de sesión activa única: `recording/start` retorna 409 si ya existe sesión en `recording` o `grace_period`. Query con lock pesimista para evitar race conditions.
- Validación de TTL restante al iniciar grabación (> 5 minutos requeridos).
- Room TTL delayed job: programado al crear sala, almacena `jobId` en `rooms.ttl_job_id`, cancelable al cerrar sala.
- Recording Limit delayed job: programado al iniciar grabación, almacena `jobId` en `recording_sessions.limit_job_id`, cancelable al detener grabación.
- Forzado de stop por Room TTL con grabación activa (flujo completo: time-expired → stop → grace period → processing → cierre).
- Control del anfitrión (validado por `HostGuard`): botón iniciar/finalizar grabación con cuenta regresiva.
- Worker Python con endpoint REST `POST /api/process`: concatenación de chunks por participante con FFmpeg.
- Bridge BullMQ → HTTP en NestJS para disparar procesamiento.
- Generación de pista individual (FLAC por defecto) y mezcla final.
- Actualización de `RecordingService` para múltiples sesiones: `getCurrentSession(roomId)` filtra por status, chunks se validan contra `session_id`, processing de sesión 1 no interfiere con sesión 2.
- Endpoint `GET /api/rooms/:id/sessions` para listar sesiones.
- Prueba de sonido básica (grabar y reproducir).
- VAD básico (umbral RMS) con registro de eventos en base de datos durante grabación.
- Hard limits globales vía variables de entorno (`MAX_ROOM_DURATION_HARD_LIMIT`, `MAX_RECORDING_DURATION_HARD_LIMIT`).

**Entregable (MVP):** Sesión completa de grabación con pistas individuales, mezcla final y metadatos VAD disponibles para descarga. Múltiples sesiones por sala funcionales. Límites de tiempo con enforcement server-side.

### 11.3 Hito 3 — Resiliencia y Reconexiones

**Duración estimada:** 3-4 semanas

**Objetivo:** Garantizar robustez ante fallos de conexión e interacción correcta con límites de tiempo.

- Reconexión automática de WebSocket con backoff exponencial y re-autenticación (JWT de host con refresh, JWT efímero de guest desde sessionStorage).
- Almacenamiento temporal de JWT de guest en `sessionStorage` durante grabación activa.
- Reenvío automático de chunks pendientes tras reconexión.
- Restablecimiento de Transports mediasoup (Producer/Consumer) al reconectarse.
- Período de gracia post-sesión para chunks pendientes (5 minutos por defecto, configurable en room_settings).
- Generación automática de silencio en huecos de desconexión.
- Indicadores visuales de estado de conexión por participante.
- Recovery de delayed jobs tras restart del servidor: consultar salas activas y sesiones con jobs pendientes, recalcular delays, reprogramar.
- Reconexión durante expiración de límites: manejo de edge cases (sala cerrada, countdown en progreso, grace period de sesión forzada).
- Tests de integración simulando desconexiones (escenarios 1-4 de §6.4.1) e interacción con límites de tiempo.

**Entregable:** El sistema tolera desconexiones sin pérdida de audio, generando pistas completas y sincronizadas. Los delayed jobs sobreviven reinicios del servidor.

### 11.4 Hito 4 — Interacción en Sala y UX

**Duración estimada:** 2-3 semanas

**Objetivo:** Completar las funciones de interacción de la sala y warnings de tiempo.

- Botón de levantar la mano con animación visual.
- Botón de marca de tiempo con etiqueta opcional.
- Botón de sugerir finalización con notificación al anfitrión.
- Prueba de sonido mejorada (reproducir en interfaz + opción de descarga).
- Sistema de avatares: subida de imagen idle/hablando con alternancia por VAD.
- Avatar genérico con indicador de borde iluminado como fallback.
- Indicador visual de nivel de audio en tiempo real por participante.
- Cronómetro de sesión visible durante grabación.
- Warnings de tiempo en frontend: banners con countdown para recording limit (visible al host) y room TTL (visible a todos). Estilos diferenciados para no confundir ambos warnings.
- Indicador de sesiones en la UI: número de sesión actual, estado de sesiones anteriores, acceso a descarga de sesiones completadas.
- Exportación de eventos VAD como JSON (con schema definido en §6.7.3) junto con pistas de audio.
- Mejoras de UX: transiciones, feedback visual, sonidos de notificación.

**Entregable:** Experiencia completa de sala con avatares animados, warnings de tiempo, y todas las interacciones diseñadas.

### 11.5 Hito 5 — Procesamiento Avanzado y Notificaciones

**Duración estimada:** 3-4 semanas

**Objetivo:** Mejorar la calidad del audio procesado y automatizar notificaciones.

- Tabla `processing_presets` y endpoint de configuración pre-procesamiento.
- Reducción de ruido con RNNoise (FFmpeg arnndn) en el worker — genera versión raw y denoised.
- Normalización de volumen a -16 LUFS con `loudnorm` de FFmpeg.
- Exportación configurable: FLAC (default), WAV, MP3. Siempre genera MP3 de preview adicional.
- Incluir marcas de tiempo y eventos VAD en los metadatos del audio exportado.
- Sistema de notificaciones por email con enlaces de descarga (presigned URLs de SeaweedFS). Agrupación de notificaciones si múltiples sesiones completan en < 5 minutos.
- Página de descarga con listado de sesiones de la sala (por sesión, por participante, formatos, variantes raw/denoised).
- Sesiones en `processing` muestran indicador, sesiones en `failed` muestran opción de reprocesar (solo host).
- Limpieza automática de chunks temporales en SeaweedFS (configurable, no antes de que las pistas procesadas estén confirmadas).

**Entregable:** Pistas de audio con calidad profesional, notificaciones automáticas y descarga organizada con soporte multi-sesión.

### 11.6 Hito 6 — Reducción de Ruido en Cliente y Optimización

**Duración estimada:** 2-3 semanas

**Objetivo:** Mejorar la experiencia en vivo y optimizar rendimiento general.

- RNNoise en WebAssembly como AudioWorklet para comunicación en vivo (solo afecta SFU, no grabación).
- Opción de activar/desactivar reducción de ruido en vivo por participante.
- Optimización de consumo de memoria y CPU en el cliente.
- Benchmark y profiling de rendimiento bajo carga (validar RNF-01 con mediasoup).
- Pruebas de compatibilidad cross-browser (Chrome, Firefox, Edge, Safari).
- Implementación de métricas Prometheus (§10.2) y health checks (§10.3).
- Structured logging con pino en producción.

**Entregable:** Aplicación optimizada con reducción de ruido en vivo opcional, rendimiento validado y observabilidad implementada.

### 11.7 Hito 7 — Despliegue y Lanzamiento

**Duración estimada:** 2-3 semanas

**Objetivo:** Puesta en producción estable.

- Configuración de infraestructura cloud (VPS + SeaweedFS + dominio).
- Caddy como reverse proxy: terminación SSL automática, servir frontend estático, proxy a NestJS, WebSockets y mediasoup.
- Pipeline CI/CD con GitHub Actions (lint, test, build, deploy).
- STUN/TURN server propio (coturn) para NAT traversal con mediasoup.
- Health checks y alertas (§10.4).
- Suite de tests completa ejecutándose en CI (unit + integration + E2E).
- Documentación de usuario y guía de uso.
- Beta testing con sesiones de podcast reales.

**Entregable:** Plataforma en producción lista para uso real, protegida por autenticación.

---

## 12. Matriz de Trazabilidad: Requerimientos vs Hitos

### 12.1 Requerimientos Funcionales

| Req. | Descripción | H1 | H2 | H3 | H4 | H5 | H6 | H7 |
|------|-------------|----|----|----|----|----|----|-----|
| RF-01 | Crear sala con enlace de invitación (host autenticado) | ● | | | | | | |
| RF-02 | Comunicación de voz en tiempo real (SFU) | ● | | ○ | | | | |
| RF-03 | Grabación local de audio individual | | ● | | | | | |
| RF-04 | Envío de chunks al servidor | | ● | ○ | | | | |
| RF-05 | Almacenamiento en S3 (SeaweedFS) | | ● | | | | | |
| RF-06 | Control anfitrión (inicio/fin + countdown) | | ● | | | | | |
| RF-07 | Prueba de sonido (escuchar/descargar) | | ○ | | ● | | | |
| RF-08 | Muteo/desmuteo de micrófono | ● | | | | | | |
| RF-09 | Levantar la mano | | | | ● | | | |
| RF-10 | Marca de tiempo (timestamp) | | | | ● | ○ | | |
| RF-11 | Sugerencia de finalización | | | | ● | | | |
| RF-12 | Reconexión + silencio automático | | | ● | | | | |
| RF-13 | Mezcla final de todos los participantes | | ● | | | ○ | | |
| RF-14 | Notificación con enlace de descarga | | | | | ● | | |
| RF-15 | Período de gracia post-sesión | | | ● | | | | |
| RF-16 | Reducción de ruido | | | | | ● | ○ | |
| RF-17 | Detección de actividad de voz (VAD) | | ● | | ○ | | | |
| RF-18 | Avatares animados (idle/hablando) | | | | ● | | | |
| RF-19 | Registro de eventos VAD para post-producción | | ● | | ○ | | | |
| RF-20 | Registro de usuario host | ● | | | | | | |
| RF-21 | Login para hosts | ● | | | | | | |
| RF-22 | Múltiples sesiones por sala | | ● | | | | | |
| RF-23 | Límite de tiempo por grabación | | ● | ○ | ○ | | | |
| RF-24 | Límite de tiempo por sala (TTL) | | ● | ○ | ○ | | | |
| RF-25 | Warnings de tiempo al cliente | | | | ● | | | |
| RF-26 | Listado de sesiones por sala | | ● | | ○ | | | |
| RF-27 | Cierre automático por TTL | | ● | ○ | | | | |

### 12.2 Requerimientos No Funcionales

| Req. | Descripción | H1 | H2 | H3 | H4 | H5 | H6 | H7 |
|------|-------------|----|----|----|----|----|----|-----|
| RNF-01 | Bajo consumo de recursos en cliente | | ○ | | | | ● | |
| RNF-02 | Latencia < 300ms | ● | | ○ | | | ○ | |
| RNF-03 | Tolerancia a pérdida de paquetes | | ○ | ● | | | | |
| RNF-04 | Disponibilidad > 99.5% | | | | | | | ● |
| RNF-05 | Compatibilidad cross-browser | | ○ | | | | ● | |
| RNF-06 | Procesamiento < 2x duración | | | | | ● | ○ | |
| RNF-07 | Escalabilidad (múltiples salas) | | | | | | | ● |

### 12.3 Resumen de Cobertura por Hito

| Hito | RF Principales | RF Parciales | RNF Abordados |
|------|---------------|-------------|---------------|
| H1 - Infraestructura + Auth + SFU | RF-01, RF-02, RF-08, RF-20, RF-21 | — | RNF-02, RNF-05 |
| H2 - Grabación (MVP) | RF-03, RF-04, RF-05, RF-06, RF-13, RF-17, RF-19, RF-22, RF-23, RF-24, RF-26, RF-27 | RF-07 | RNF-01, RNF-03, RNF-05 |
| H3 - Resiliencia | RF-12, RF-15 | RF-02, RF-04, RF-23, RF-24, RF-27 | RNF-03 |
| H4 - Interacción UX | RF-07, RF-09, RF-10, RF-11, RF-18, RF-25 | RF-17, RF-19, RF-23, RF-24, RF-26 | — |
| H5 - Procesamiento | RF-14, RF-16 | RF-10, RF-13 | RNF-06 |
| H6 - Optimización | — | RF-16 | RNF-01, RNF-02, RNF-05, RNF-06 |
| H7 - Despliegue | — | — | RNF-04, RNF-07 |

**Nota:** Esta matriz debe actualizarse al inicio de cada hito durante la planificación, incorporando cambios en alcance o repriorización según el feedback de las iteraciones anteriores.

---

## 13. Iteraciones Futuras (Post-Lanzamiento)

Las siguientes funcionalidades se planean para iteraciones posteriores al lanzamiento, según demanda y feedback de usuarios:

| Funcionalidad | Descripción | Complejidad |
|--------------|-------------|-------------|
| OAuth para hosts | Login con Google, GitHub u otros providers vía Passport strategies adicionales | Baja |
| Verificación de email | Confirmar email del host al registrarse, reset de password | Baja |
| Planes comerciales | Tabla `plans` con límites de tiempo (minutos de grabación/semana, tiempo de sala/semana). `users.plan_id` hereda topes a `room_settings` | Media |
| Identity provider externo | Migrar de Passport local a Keycloak/Casdoor si se necesita SSO multi-aplicación o federation corporativa (modelo on-premise) | Media-Alta |
| Cuenta opcional para guests | Registro opcional que precarga nombre, email y avatares al unirse a salas | Baja |
| Vinculación retroactiva de guests | Asociar participaciones anteriores a una cuenta nueva mediante `participants.email` | Baja |
| Avatares animados avanzados | Multi-frame con modulación por volumen (3-4 estados de boca), movimiento de ojos | Media |
| Generación de video | Renderizado automático de video con avatares animados usando eventos VAD | Alta |
| App móvil | Versión React Native o Capacitor para iOS/Android | Alta |
| Captura de video | Grabación de cámara individual + composición automática | Alta |
| Post-procesamiento auto | Mezcla inteligente, compresores, EQ automático | Media |
| Transcripción automática | Speech-to-text con Whisper por participante | Media |
| Chat de texto en sala | Mensajes de texto durante la sesión | Baja |
| Integración DAW | Exportar proyecto compatible con Audacity / Reaper / Logic | Media |
| Grabación programada | Agendar sesiones con recordatorios automáticos | Baja |
| Panel de administración | Dashboard con historial de sesiones, estadísticas de uso | Media |
| Migración a S3/R2 | Si el volumen de datos crece, migrar almacenamiento vía `StoragePort` sin cambios en lógica | Baja |
| Política de retención | Limpieza automática de sesiones antiguas y chunks, configurable por plan | Media |

---

## 14. Resumen del Timeline

Estimación total desde inicio hasta lanzamiento: **22-31 semanas (~5.5-8 meses)** con un desarrollador individual.

| Hito | Nombre | Duración | Acumulado |
|------|--------|----------|-----------|
| 1 | Infraestructura, Auth y Comunicación SFU | 5-6 sem | 5-6 sem |
| 2 | Grabación, Chunks, Multi-sesión y Límites (MVP) | 5-6 sem | 10-12 sem |
| 3 | Resiliencia, Reconexiones y Recovery | 3-4 sem | 13-16 sem |
| 4 | Interacción en Sala, UX y Warnings | 2-3 sem | 15-19 sem |
| 5 | Procesamiento Avanzado y Notificaciones | 3-4 sem | 18-23 sem |
| 6 | Reducción de Ruido en Cliente y Optimización | 2-3 sem | 20-26 sem |
| 7 | Despliegue y Lanzamiento | 2-3 sem | 22-29 sem |

**Nota:** Las estimaciones asumen un desarrollador individual trabajando a tiempo completo. El Hito 1 incluye autenticación con Passport y la integración de mediasoup (SFU). El Hito 2 absorbe la funcionalidad de multi-sesión y límites de tiempo (anteriormente distribuida en un ADR separado).

El MVP funcional (Hitos 1 + 2) se alcanza en aproximadamente **10-12 semanas**, lo que permite validar la propuesta con sesiones de podcast reales en un VPS protegido por autenticación.

---

## 15. Estimación de Costos de Infraestructura

Estimación mensual para un escenario de uso moderado (10 sesiones/semana, 5 participantes, 1 hora promedio por episodio):

| Servicio | Especificación | Costo Estimado/mes |
|----------|---------------|-------------------|
| VPS (API + WebSocket + mediasoup) | 4 vCPU, 8 GB RAM (mediasoup requiere más recursos que señalización pura) | $20 - $40 USD |
| VPS (Worker Python) | 2 vCPU, 4 GB RAM (procesamiento FFmpeg) | $15 - $25 USD |
| PostgreSQL | Managed o en VPS principal | $0 - $15 USD |
| Dragonfly | En VPS principal | $0 - $10 USD |
| SeaweedFS | Self-hosted en VPS, ~100-200 GB de datos | $10 - $20 USD (disco adicional) |
| TURN Server | coturn self-hosted en VPS o servicio (Twilio/Xirsys) | $0 - $30 USD |
| Dominio + SSL | Let's Encrypt (gratuito) + dominio | $1 - $2 USD |
| Email (notificaciones) | Resend / SendGrid tier gratuito | $0 USD |
| **TOTAL ESTIMADO** | | **$46 - $142 USD** |

**Nota:** El VPS principal requiere más recursos que en versiones anteriores debido a mediasoup, que ejecuta workers nativos de C++ para el procesamiento de media. Para escalar, mediasoup soporta múltiples workers distribuidos en cores del CPU. El costo de SeaweedFS se reduce a disco, ya que se ejecuta en VPS existente. La autenticación con Passport no añade costos adicionales de infraestructura.

---

## 16. Conclusiones

PodSync propone una solución integral al problema de la grabación remota de podcasts, abordando las limitaciones fundamentales del flujo actual basado en Discord + OBS. Los principios de diseño clave son:

1. **Grabación local primero:** Al grabar directamente del micrófono en cada dispositivo, la calidad del audio es independiente de la conexión a Internet.
2. **Envío incremental:** Los chunks de 5 segundos minimizan el riesgo de pérdida de audio y permiten recuperación granular.
3. **Separación de concerns:** La comunicación en vivo (mediasoup SFU) y la grabación (MediaRecorder) son flujos independientes, evitando que problemas en uno afecten al otro.
4. **Tolerancia a fallos:** El sistema de buffers, ACKs, y generación de silencio asegura que siempre se produce un resultado utilizable, con un periodo de gracia de 5 minutos para recibir datos pendientes.
5. **Bajo consumo de recursos:** El uso de un SFU (1 uplink por cliente vs N-1 en mesh), Web Workers, codecs eficientes (Opus), y FLAC como formato de exportación mantiene la carga del cliente y el almacenamiento en niveles óptimos.
6. **Audio original preservado:** Las decisiones de procesamiento (reducción de ruido, normalización, formato) son configurables y reversibles. Los chunks crudos nunca se destruyen, permitiendo reprocesamiento en cualquier momento.
7. **Identidad asimétrica:** Hosts con cuenta persistente para protección de recursos y trazabilidad. Guests efímeros para minimizar la fricción de entrada. El diseño habilita un path claro hacia planes comerciales y cuentas opcionales para guests.
8. **Múltiples sesiones por sala:** Flexibilidad para grabar varios episodios o repetir tomas sin recrear la sala, con límites de tiempo configurables y enforcement server-side.
9. **Observabilidad desde el diseño:** Structured logging, métricas y health checks integrados, no añadidos a posteriori.

Con un desarrollo incremental de ~5.5-8 meses y un MVP disponible en ~2.5-3 meses, el proyecto permite validación temprana y mejora continua basada en uso real. La arquitectura está diseñada para evolucionar hacia funcionalidades futuras (planes comerciales, OAuth, video, apps móviles, identity providers externos) sin reescrituras fundamentales, y la abstracción de almacenamiento (`StoragePort`) facilita migrar a cualquier proveedor S3-compatible cuando el volumen lo justifique.

---

*Fin del documento — PodSync TDD v1.6*
