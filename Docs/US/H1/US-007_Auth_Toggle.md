# US-007 — Modo Desarrollo sin Autenticación

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** desarrollador,
> **quiero** poder desactivar la autenticación con una variable de entorno `AUTH_ENABLED=false`,
> **para** agilizar el desarrollo local sin necesidad de registrar/logear usuarios.

**Referencia TDD:** §7.9 (Modo de Desarrollo sin Autenticación)
**Prioridad:** P2-Medium
**Estimación total:** M (4–8h)
**Dependencias:** US-005

### Criterios de Aceptación

1. Con `AUTH_ENABLED=false`, `POST /api/rooms` no requiere JWT y crea la sala con `owner_user_id = null`.
2. El `HostGuard` valida basándose en `jwt.role === 'host'` del JWT efímero en modo dev.
3. Al iniciar con `AUTH_ENABLED=false`, se emite un log warning: `"⚠️ Auth disabled — development mode only"`.
4. `AUTH_ENABLED` tiene default `true`.
5. Los endpoints de auth (`/register`, `/login`, `/refresh`, `/me`) siguen funcionando aunque auth esté desactivado (no se desactivan, solo se bypasea la validación en endpoints de negocio).

### Tareas

#### TASK-016: Implementar toggle AUTH_ENABLED y Guards condicionales

| Campo | Valor |
|-------|-------|
| **ID** | TASK-016 |
| **Tamaño** | M |
| **Prioridad** | P2-Medium |
| **Dependencias** | TASK-014 |

**Especificación de implementación:**

1. Crear un guard `OptionalJwtAuthGuard` que:
   - Si `AUTH_ENABLED=true`, se comporta como `JwtAuthGuard` (rechaza sin JWT).
   - Si `AUTH_ENABLED=false`, permite el paso sin JWT y simula un usuario con role host.

   ```typescript
   @Injectable()
   export class OptionalJwtAuthGuard extends AuthGuard('jwt') {
     constructor(private configService: ConfigService) {
       super();
     }

     canActivate(context: ExecutionContext) {
       const authEnabled = this.configService.get<string>('AUTH_ENABLED', 'true') === 'true';
       if (!authEnabled) {
         // Bypass: attach mock user to request
         const request = context.switchToHttp().getRequest();
         request.user = { userId: null, email: null, type: 'host' };
         return true;
       }
       return super.canActivate(context);
     }
   }
   ```

2. Modificar `HostGuard` para manejar el caso `userId = null` cuando auth está desactivado.

3. En `main.ts` (o en `AppModule.onModuleInit`), emitir warning si `AUTH_ENABLED=false`:
   ```typescript
   if (configService.get('AUTH_ENABLED') === 'false') {
     logger.warn('⚠️ Auth disabled — development mode only');
   }
   ```

**Tests TDD:**

```typescript
describe('OptionalJwtAuthGuard (AUTH_ENABLED=false)', () => {
  it('should allow access without JWT when auth is disabled', async () => {
    // Test con módulo configurado con AUTH_ENABLED=false
    await request(app.getHttpServer())
      .post('/api/rooms')
      .send({})
      .expect(201); // no JWT needed
  });
});

describe('OptionalJwtAuthGuard (AUTH_ENABLED=true)', () => {
  it('should reject access without JWT when auth is enabled', async () => {
    await request(app.getHttpServer())
      .post('/api/rooms')
      .send({})
      .expect(401);
  });
});
```
