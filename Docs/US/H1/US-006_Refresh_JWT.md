# US-006 — Renovación de JWT y Gestión de Sesión

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** host autenticado,
> **quiero** renovar mi JWT automáticamente usando un refresh token,
> **para** mantener mi sesión activa sin necesidad de reingresar credenciales cada 7 días.

**Referencia TDD:** §7.2 (JWT del Host, Refresh token), §6.2.1 (`/api/auth/refresh`, `/api/auth/me`)
**Prioridad:** P1-High
**Estimación total:** L (1–2 días)
**Dependencias:** US-005

### Criterios de Aceptación

1. `POST /api/auth/refresh` con cookie de refresh token válido retorna nuevo JWT y rota el refresh token (emite nuevo token, invalida el anterior).
2. Si el refresh token es inválido, expirado o no existe, retorna `401 Unauthorized`.
3. `GET /api/auth/me` con JWT válido retorna `{ userId, email, createdAt }`.
4. `GET /api/auth/me` sin JWT o con JWT expirado retorna `401`.

### Tareas

#### TASK-014: Implementar JwtStrategy y JwtAuthGuard

| Campo | Valor |
|-------|-------|
| **ID** | TASK-014 |
| **Tamaño** | M |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-012 |

**Especificación de implementación:**

1. Crear `JwtStrategy`:
   ```typescript
   @Injectable()
   export class JwtStrategy extends PassportStrategy(Strategy) {
     constructor(configService: ConfigService) {
       super({
         jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
         ignoreExpiration: false,
         secretOrKey: configService.get<string>('JWT_SECRET'),
       });
     }

     async validate(payload: JwtPayload) {
       return {
         userId: payload.sub,
         email: payload.email,
         type: payload.type,
       };
     }
   }
   ```

2. Crear `JwtAuthGuard` como wrapper de `AuthGuard('jwt')`.

3. Crear interfaz `JwtPayload`:
   ```typescript
   export interface JwtPayload {
     sub: string;       // userId o participantId
     email?: string;
     type: 'host' | 'guest';
     role?: 'host' | 'guest';
     roomId?: string;   // solo para guest
     displayName?: string; // solo para guest
     iat: number;
     exp: number;
   }
   ```

**Tests TDD:**

```typescript
describe('JwtStrategy', () => {
  it('should validate a valid JWT payload and return user data', async () => {
    const payload = { sub: 'uuid', email: 'host@test.com', type: 'host' };
    const result = await strategy.validate(payload);
    expect(result.userId).toBe('uuid');
    expect(result.type).toBe('host');
  });
});
```

---

#### TASK-015: Implementar endpoints refresh y me

| Campo | Valor |
|-------|-------|
| **ID** | TASK-015 |
| **Tamaño** | M |
| **Prioridad** | P1-High |
| **Dependencias** | TASK-014 |

**Especificación de implementación:**

1. `POST /api/auth/refresh`:
   - Extraer refresh token de la cookie `refresh_token`.
   - Buscar en la tabla `RefreshToken` un registro cuyo hash coincida y no esté expirado.
   - Si válido: generar nuevo JWT, generar nuevo refresh token, eliminar el anterior, almacenar el nuevo.
   - Si inválido: retornar `401`.
   - Establecer nuevo cookie con el refresh token rotado.

2. `GET /api/auth/me`:
   ```typescript
   @UseGuards(JwtAuthGuard)
   @Get('me')
   async me(@Request() req) {
     const user = await this.usersService.findById(req.user.userId);
     if (!user) throw new UnauthorizedException();
     return {
       userId: user.id,
       email: user.email,
       createdAt: user.createdAt,
     };
   }
   ```

3. Para la extracción de cookies en Fastify, registrar `@fastify/cookie`:
   ```bash
   pnpm add @fastify/cookie
   ```
   Registrar en `main.ts`:
   ```typescript
   await app.register(require('@fastify/cookie'));
   ```

**Tests TDD (integration):**

```typescript
describe('POST /api/auth/refresh', () => {
  it('should return new JWT with valid refresh token cookie', async () => {
    const registerRes = await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: 'host@test.com', password: 'securePass123' });

    const cookies = registerRes.headers['set-cookie'];

    const refreshRes = await request(app.getHttpServer())
      .post('/api/auth/refresh')
      .set('Cookie', cookies)
      .expect(200);

    expect(refreshRes.body.jwt).toBeDefined();
    expect(refreshRes.body.jwt).not.toBe(registerRes.body.jwt);
  });

  it('should return 401 with no refresh token', async () => {
    await request(app.getHttpServer())
      .post('/api/auth/refresh')
      .expect(401);
  });
});

describe('GET /api/auth/me', () => {
  it('should return user profile with valid JWT', async () => {
    const registerRes = await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: 'host@test.com', password: 'securePass123' });

    const res = await request(app.getHttpServer())
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${registerRes.body.jwt}`)
      .expect(200);

    expect(res.body.email).toBe('host@test.com');
  });

  it('should return 401 without JWT', async () => {
    await request(app.getHttpServer())
      .get('/api/auth/me')
      .expect(401);
  });
});
```
