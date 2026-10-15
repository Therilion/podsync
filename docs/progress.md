# PodSync — Seguimiento del Desarrollo

Estado del plan de hitos del TDD (`docs/podsync-tdd.md` §11). Este documento solo registra el avance; el alcance de cada hito lo define el TDD.

**Leyenda:** ⬜ pendiente · 🟨 en curso · ✅ completado · ⛔ bloqueado

**Última actualización:** 2026-10-15

---

## 1. Resumen

| Hito | Nombre                                               | Estimado | Estado | Inicio | Fin |
| ---- | ---------------------------------------------------- | -------- | ------ | ------ | --- |
| F0   | Spikes de validación                                 | 1 sem    | ⬜     | —      | —   |
| H1   | Infraestructura, Auth y Comunicación SFU             | 4-5 sem  | ⬜     | —      | —   |
| H2   | Grabación, Procesamiento y Entrega (MVP)             | 5-6 sem  | ⬜     | —      | —   |
| H3   | Resiliencia, Reconexiones y TTL de Sala              | 3-4 sem  | ⬜     | —      | —   |
| H4   | Interacción en Sala, VAD y UX                        | 2-3 sem  | ⬜     | —      | —   |
| H5   | Procesamiento Avanzado, Descargas y Notificaciones   | 3-4 sem  | ⬜     | —      | —   |
| H6   | Reducción de Ruido en Cliente, Safari y Optimización | 2-3 sem  | ⬜     | —      | —   |
| H7   | Endurecimiento y Lanzamiento                         | 2-3 sem  | ⬜     | —      | —   |

---

## 2. Decisiones abiertas (TDD §17.1)

| ID   | Decisión                                         | Se resuelve con | Bloquea | Estado | Resolución |
| ---- | ------------------------------------------------ | --------------- | ------- | ------ | ---------- |
| D-01 | Valores de los hard limits globales              | Owner           | H2, H3  | ⬜     | —          |
| D-02 | Procesamiento de captura de audio                | SPIKE-01        | H2      | ⬜     | —          |
| D-03 | Política ante cuota de IndexedDB llena           | Owner           | H2      | ⬜     | —          |
| D-04 | Deriva de reloj aceptable en el MVP              | SPIKE-01        | H2      | ⬜     | —          |
| D-05 | Métrica de RNF-08                                | SPIKE-01        | H2      | ⬜     | —          |
| D-06 | Red de mediasoup y publicación de puertos        | SPIKE-02        | H1, H2  | ⬜     | —          |

---

## 3. Fase 0 — Spikes de validación (TDD §11.0)

| ID       | Tarea                                      | Estado | Rama / informe | Notas |
| -------- | ------------------------------------------ | ------ | -------------- | ----- |
| SPIKE-01 | Grabación, reconstrucción y alineación     | ⬜     | —              | Cierra D-02, D-04, D-05 |
| SPIKE-02 | mediasoup en el VPS real                   | ⬜     | —              | Cierra D-06 |
| —        | Informes de spikes y actualización de §17  | ⬜     | —              | —     |

---

## 4. Hito 1 — Infraestructura, Autenticación y Comunicación Básica (TDD §11.1)

| ID | Tarea                                                                 | Estado | PR | Notas |
| -- | --------------------------------------------------------------------- | ------ | -- | ----- |
| —  | Setup del monorepo (Turborepo + pnpm, frontend, API, tipos compartidos) | ⬜   | —  | —     |
| —  | CI mínimo (lint, type-check, tests, validación de PR y commits)       | ⬜     | —  | —     |
| —  | release-please en modo manifest                                       | ⬜     | —  | —     |
| —  | Docker Compose (PostgreSQL, Dragonfly, SeaweedFS)                     | ⬜     | —  | Puertos de mediasoup según SPIKE-02 |
| —  | Esquema Prisma inicial                                                | ⬜     | —  | —     |
| —  | `AuthModule` y endpoints `/auth/*`, seed de cuentas                   | ⬜     | —  | —     |
| —  | Modelo de tokens, `RoomAccessPolicy` y guards                         | ⬜     | —  | Test-first |
| —  | `AUTH_ENABLED` con bloqueo en producción                              | ⬜     | —  | —     |
| —  | API REST de salas                                                     | ⬜     | —  | —     |
| —  | WebSocket Gateway `/ws` con heartbeat                                 | ⬜     | —  | —     |
| —  | Integración de mediasoup y voz SFU entre 2+ participantes             | ⬜     | —  | —     |
| —  | `StoragePort` con implementación para SeaweedFS                       | ⬜     | —  | —     |
| —  | Interfaz mínima (login, dashboard, unirse, participantes, mute)       | ⬜     | —  | —     |

---

## 5. Hitos 2 a 7

Las tareas de cada hito se desglosan al empezarlo, a partir de su sección en el TDD.

| Hito | Sección del TDD | Entregable |
| ---- | --------------- | ---------- |
| H2   | §11.2           | Sesión completa con pistas alineadas y mezcla descargables por el host; despliegue en el VPS |
| H3   | §11.3           | Tolerancia a desconexiones y recargas sin pérdida de audio; TTL de sala |
| H4   | §11.4           | Experiencia de sala completa: avatares, VAD y warnings de tiempo |
| H5   | §11.5           | Audio de calidad profesional, notificaciones y descargas para todos los participantes |
| H6   | §11.6           | Reducción de ruido en vivo, soporte de Safari, rendimiento y observabilidad |
| H7   | §11.7           | Producción estable con registro público y autenticación endurecida |

---

## 6. Registro de avance

Una entrada por hecho relevante (tarea cerrada, decisión tomada, bloqueo), la más reciente arriba.

| Fecha      | Hito | Evento |
| ---------- | ---- | ------ |
| 2026-10-15 | —    | Se crea este documento de seguimiento. |
