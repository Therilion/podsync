# Constitución de PodSync

**Versión:** 1.0.0
**Ratificada:** 2026-10-12
**Última modificación:** 2026-10-12
**Owner:** Therilion

Este documento define las reglas no negociables de PodSync. Toda spec, plan, tarea, PR y decisión técnica debe cumplirlas. Si una propuesta incumple un principio, se rechaza o se modifica primero esta constitución (ver §5).

La fuente de verdad técnica es `docs/podsync-tdd.md` (TDD). La constitución dice **qué no se puede romper**; el TDD dice **qué se construye y cómo**.

---

## 1. Principios

### I. Grabación local primero

Cada participante graba su audio en su propio dispositivo (MediaRecorder). La calidad de la pista grabada nunca depende de la calidad de la conexión en vivo.

- La comunicación en vivo (mediasoup) y la grabación son flujos independientes. Un fallo en uno no puede detener al otro.
- La señalización (`/ws`) y el transporte de chunks (`/ws/chunks`) usan canales separados.

**Por qué:** es la razón de existir del producto (TDD §2). Si la red decide la calidad, PodSync no aporta nada frente a Discord + OBS.

### II. Ningún dato de audio se pierde en silencio

- Un chunk solo se borra del buffer local (IndexedDB) después de que el servidor confirma su recepción (ACK).
- El control de flujo usa `chunk:nack` y reintentos; superar la tasa nunca provoca desconexión ni descarte.
- Si un dato no puede guardarse (cuota llena, error de almacenamiento), se avisa al participante y al host. Prohibido descartar sin aviso.
- Los chunks crudos en SeaweedFS nunca se destruyen como efecto del procesamiento. Todo procesamiento (ruido, normalización, formato) debe poder repetirse desde los chunks originales.
- La recepción de chunks es idempotente: el mismo `sequence_number` produce un único objeto y una única fila.

**Por qué:** una sesión de podcast no se puede repetir. Perder audio es el peor fallo posible del sistema.

### III. El estado vive en PostgreSQL; el servidor decide

- El estado de salas y sesiones vive en PostgreSQL. Las colas (BullMQ/Dragonfly) solo ejecutan trabajo; perder la cola no puede dejar estado inconsistente.
- Los límites de tiempo, transiciones de sesión y cierres de sala se aplican en el servidor mediante el sweeper idempotente. El cliente nunca es la autoridad.
- Las invariantes críticas se garantizan en la base de datos (índices únicos, FKs), no solo en código. Ejemplo: una única sesión activa por sala.
- Las líneas de tiempo usan el reloj del servidor (T0) como referencia.

**Por qué:** elimina errores por timers perdidos, reinicios y clientes manipulados (TDD §16.6).

### IV. Seguridad por defecto

- Toda acción sobre una sala verifica ownership o membresía en **esa** sala concreta, mediante `RoomAccessPolicy` y sus guards. Ningún endpoint ni evento WebSocket queda sin guard.
- Cada tipo de token se acepta solo donde corresponde (account token vs participant token).
- La identidad declarada por el cliente (p. ej. el header de un chunk) se valida siempre contra el token del socket.
- Los secretos solo viven en variables de entorno. Nunca en el código, en el repo ni en el Docker Compose de producción.
- Los endpoints internos (`/api/internal/*`) nunca se exponen fuera de la red interna.
- El modo sin autenticación (`AUTH_ENABLED=false`) nunca puede arrancar en producción.

**Por qué:** el sistema maneja voz de personas y recursos de servidor con coste real.

### V. Observabilidad desde el diseño

Cada feature nueva incluye, en el mismo PR:

- logs estructurados (pino / JSON) con los campos de correlación del TDD §10.1 (`session_id`, `participant_id`, `user_id` cuando aplica);
- métricas para los eventos relevantes (TDD §10.2);
- health check si introduce una dependencia nueva.

Prohibido registrar datos sensibles sin redactar (emails, tokens, contraseñas).

**Por qué:** los fallos de audio y red son difíciles de reproducir. Sin datos, no se pueden diagnosticar.

### VI. Simplicidad justificada

- No se añade un servicio, framework o dependencia de runtime sin un ADR breve en `docs/adr/` que explique el problema, las alternativas y el coste.
- El stack de TDD §4.2 es el stack del proyecto. Cambiarlo requiere ADR y actualización del TDD.
- Se implementa lo que pide el hito actual. Las funcionalidades de hitos futuros o de TDD §13 no se adelantan "por si acaso".
- El acceso a almacenamiento de objetos pasa siempre por `StoragePort`.

**Por qué:** un solo desarrollador mantiene el proyecto. Cada pieza extra es coste operativo permanente.

---

## 2. Calidad y testing

### Test-first en lógica crítica

En estas áreas, el test que falla se escribe **antes** que la implementación:

- protocolo binario de chunks (parsing, validación, idempotencia);
- sweeper y transiciones de estado de salas y sesiones;
- guards, `RoomAccessPolicy` y autenticación;
- reconstrucción y alineación de pistas en el worker;
- control de flujo (ventana de envío, token bucket, NACK).

En el resto del código, los tests van en el mismo PR que el cambio.

### Gates de CI (bloquean el merge)

- Lint y type-check sin errores.
- Tests unitarios e integración en verde.
- Cobertura unitaria ≥ 80% en services y utils.
- Los escenarios críticos de TDD §9.2 que correspondan al hito tienen test.

### Estándares de código

- **TypeScript:** `strict: true`. Prohibido `any`, salvo con un comentario que justifique por qué.
- **Python:** type hints obligatorios; `ruff` como linter y formateador.
- **Idioma:** código, identificadores, comentarios y commits en inglés. Documentación del proyecto en español.

### Spikes

El código de los spikes (Fase 0 y posteriores) es desechable: nunca se mergea en `main`. Sus resultados se documentan en un informe y en TDD §17.

---

## 3. Restricciones del producto

Estas restricciones solo cambian modificando el TDD y, si afectan un principio, esta constitución:

- Máximo 5 participantes por sala.
- Navegadores del MVP: Chrome, Edge y Firefox de escritorio. Safari desde H6.
- Hosts con cuenta persistente; guests efímeros sin registro.
- Una única sesión de grabación activa por sala.
- Backend de instancia única en el MVP.
- Los límites de tiempo nunca superan los hard limits globales configurados por entorno.

---

## 4. Flujo de trabajo

### Ramas (trunk-based)

- `main` es la única rama permanente. Siempre debe compilar y pasar los gates de CI.
- Ramas de trabajo cortas, creadas desde `main`:
  - `feature/<task-id>-<short-desc>` para funcionalidad nueva;
  - `fix/<task-id>-<short-desc>` para correcciones, incluidas las urgentes.
- Una rama vive como máximo unos días. Si una tarea es más grande, se divide en PRs pequeños que dejan `main` funcionando; el trabajo incompleto visible para usuarios se oculta tras un flag.
- Prohibido hacer commit directo a `main`. Todo entra por PR.
- Cada tarea se trabaja en su propio git worktree (`../podsync-<branch-name>`), nunca en el worktree principal.

### Merge y commits

- Los PR se mergean solo con squash. La rama se borra al mergear.
- El título del PR es el mensaje del commit final, así que **debe** seguir Conventional Commits, en inglés. Un check de CI lo valida.
- Commits con Conventional Commits, en inglés.
- **Sin atribución a IA en commits.** Cuando una IA crea o redacta un commit, el mensaje no puede incluir trailers `Co-authored-by` que atribuyan a una IA o a su proveedor, ni líneas de firma como `Generated with ...` o emojis de atribución. El autor del commit es la persona que lo pide y lo revisa.
- **Sin escrituras en git ni en GitHub sin autorización.** Una IA no puede crear commits, hacer push, abrir o mergear PRs, ni hacer ninguna otra escritura en GitHub (ramas, tags, releases, issues, comentarios o ajustes del repo) sin autorización explícita del owner para esa acción concreta. Pedir un cambio en un archivo no autoriza a commitearlo. Una autorización vale solo para la acción indicada; no se extiende a acciones posteriores.
- Toda spec o cambio de OpenSpec debe referenciar los requerimientos del TDD que cubre (RF-xx / RNF-xx).

### Versionado y releases (release-please)

- Las versiones las gestiona release-please en modo manifest (`release-please-config.json` + `.release-please-manifest.json`).
- Cada paquete desplegable tiene su propia versión semver y su propio `CHANGELOG.md`. Tags con formato `<paquete>-v<versión>` (p. ej. `api-v1.2.0`).
- release-please asigna cada commit a un paquete según las rutas modificadas. Un PR que toca varios paquetes sube la versión de todos ellos.
- Mergear el release PR de release-please **es** la release. No existe otro proceso de publicación.
- "Producción" es el último tag publicado de cada paquete, no el estado de `main`. Los deploys salen siempre de tags, nunca de un push a `main`.
- Prohibido editar a mano versiones de paquetes, tags o `CHANGELOG.md`.

---

## 5. Gobierno

### Jerarquía de documentos

1. **Esta constitución:** manda en caso de conflicto.
2. **TDD (`docs/podsync-tdd.md`):** fuente de verdad técnica.
3. **Specs y cambios de OpenSpec:** deben cumplir 1 y 2.
4. **`AGENTS.md`** y demás guías: deben estar sincronizadas con 1 y 2.

Si un cambio del TDD contradice esta constitución, primero se modifica la constitución.

### Enmiendas

- Las aprueba el owner del proyecto.
- Cada enmienda actualiza la versión, la fecha de última modificación y el changelog.
- Versionado semántico:
  - **MAJOR:** se elimina o redefine un principio.
  - **MINOR:** se añade un principio o sección, o se amplía una regla.
  - **PATCH:** aclaraciones o redacción, sin cambio de significado.

### Cumplimiento

- Cada PR debe poder justificar que cumple los principios. Un incumplimiento se corrige o se documenta con un ADR que proponga la enmienda.
- La constitución se revisa al inicio de cada hito, junto con la matriz de trazabilidad del TDD (§12).

---

## Changelog

| Versión | Fecha      | Cambio                                         |
| ------- | ---------- | ---------------------------------------------- |
| 1.0.0   | 2026-10-12 | Versión inicial, derivada del TDD v1.7         |
