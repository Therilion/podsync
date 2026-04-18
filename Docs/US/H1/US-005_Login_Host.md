# US-005 — Inicio de Sesión (Login) del Host

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** host registrado,
> **quiero** iniciar sesión con mi email y contraseña,
> **para** obtener un JWT que me permita crear salas y gestionar grabaciones.

**Referencia TDD:** §7.2 (Login), §8 (Rate limiting en login)
**Prioridad:** P0-Critical
**Estimación total:** L (1–2 días)
**Dependencias:** US-004

### Criterios de Aceptación

1. `POST /api/auth/login` con credenciales válidas retorna `200 OK` con `{ userId, jwt }` y refresh token en cookie `httpOnly`.
2. Con credenciales inválidas retorna `401 Unauthorized`.
3. Rate limiting: máximo 10 intentos por email en 15 minutos. Retorna `429` tras exceder.
4. Lockout temporal de 30 minutos tras exceder el rate limit.
5. El JWT tiene la misma estructura y expiración que el generado en registro.
6. Cada login exitoso invalida refresh tokens anteriores del usuario (rotación).

### Tareas

#### TASK-012: Implementar LocalStrategy (Passport) y endpoint de login

| Campo | Valor |
|-------|-------|
| **ID** | TASK-012 |
| **Tamaño** | L |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-010 |

**Especificación de implementación:**

1. Crear `LocalStrategy` de Passport:
   ```typescript
   @Injectable()
   export class LocalStrategy extends PassportStrategy(Strategy) {
     constructor(private authService: AuthService) {
       super({ usernameField: 'email' });
     }

     async validate(email: string, password: string): Promise<User> {
       const user = await this.authService.validateUser(email, password);
       if (!user) {
         throw new UnauthorizedException('Credenciales inválidas');
       }
       return user;
     }
   }
   ```

2. Implementar `AuthService.validateUser(email, password)`:
   - Buscar usuario por email.
   - Si no existe, retornar `null`.
   - Verificar password con argon2.
   - Si no coincide, retornar `null`.
   - Si coincide, retornar el usuario.

3. Implementar `AuthService.login(user: User)`:
   - Generar JWT con payload `{ sub: user.id, email: user.email, type: 'host' }`.
   - Generar nuevo refresh token.
   - Invalidar refresh tokens previos del usuario (delete all con `userId`).
   - Almacenar nuevo refresh token hasheado.
   - Retornar `{ userId, jwt, refreshToken }`.

4. Implementar endpoint:
   ```typescript
   @UseGuards(LocalAuthGuard)
   @Post('login')
   @HttpCode(HttpStatus.OK)
   async login(
     @Request() req,
     @Res({ passthrough: true }) res: FastifyReply,
   ) {
     const result = await this.authService.login(req.user);
     res.setCookie('refresh_token', result.refreshToken, { /* same options as register */ });
     return { userId: result.userId, jwt: result.jwt };
   }
   ```

**Tests TDD (integration):**

```typescript
describe('POST /api/auth/login', () => {
  beforeEach(async () => {
    // Registrar usuario de prueba
    await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: 'host@test.com', password: 'securePass123' });
  });

  it('should login with valid credentials', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: 'host@test.com', password: 'securePass123' })
      .expect(200);

    expect(res.body.userId).toBeDefined();
    expect(res.body.jwt).toBeDefined();
  });

  it('should return 401 for wrong password', async () => {
    await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: 'host@test.com', password: 'wrongPassword' })
      .expect(401);
  });

  it('should return 401 for non-existent email', async () => {
    await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: 'nobody@test.com', password: 'securePass123' })
      .expect(401);
  });
});
```

---

#### TASK-013: Implementar rate limiting y lockout en login

| Campo | Valor |
|-------|-------|
| **ID** | TASK-013 |
| **Tamaño** | M |
| **Prioridad** | P1-High |
| **Dependencias** | TASK-012 |

**Especificación de implementación:**

1. Implementar un servicio `LoginThrottleService` que use Dragonfly (Redis) para rastrear intentos de login por email:
   - Key: `login_attempts:{email}`
   - Incrementar en cada intento fallido.
   - Expira en 15 minutos.
   - Si el count supera 10, rechazar con `429` y establecer un lockout de 30 minutos (`login_lockout:{email}` con TTL de 1800s).

2. Integrar el throttle en `LocalStrategy` o como Guard previo al login:
   ```typescript
   @Injectable()
   export class LoginThrottleGuard implements CanActivate {
     constructor(private throttleService: LoginThrottleService) {}

     async canActivate(context: ExecutionContext): Promise<boolean> {
       const request = context.switchToHttp().getRequest();
       const email = request.body?.email;
       if (!email) return true;

       const isLocked = await this.throttleService.isLockedOut(email);
       if (isLocked) {
         throw new HttpException(
           'Demasiados intentos. Intente en 30 minutos.',
           HttpStatus.TOO_MANY_REQUESTS,
         );
       }
       return true;
     }
   }
   ```

3. En el controller, registrar intentos fallidos y limpiar el contador en login exitoso:
   ```typescript
   // Después de login exitoso:
   await this.throttleService.resetAttempts(email);
   // Después de login fallido (en el catch o en el guard):
   await this.throttleService.recordFailedAttempt(email);
   ```

**Tests TDD:**

```typescript
describe('Login rate limiting', () => {
  it('should allow 10 failed attempts', async () => {
    for (let i = 0; i < 10; i++) {
      await request(app.getHttpServer())
        .post('/api/auth/login')
        .send({ email: 'host@test.com', password: 'wrong' })
        .expect(401);
    }
  });

  it('should return 429 after 10 failed attempts', async () => {
    for (let i = 0; i < 10; i++) {
      await request(app.getHttpServer())
        .post('/api/auth/login')
        .send({ email: 'host@test.com', password: 'wrong' });
    }

    await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: 'host@test.com', password: 'wrong' })
      .expect(429);
  });

  it('should reset counter on successful login', async () => {
    for (let i = 0; i < 5; i++) {
      await request(app.getHttpServer())
        .post('/api/auth/login')
        .send({ email: 'host@test.com', password: 'wrong' });
    }

    await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: 'host@test.com', password: 'securePass123' })
      .expect(200);

    // Should not be locked after successful login
    await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: 'host@test.com', password: 'wrong' })
      .expect(401); // Not 429
  });
});
```
