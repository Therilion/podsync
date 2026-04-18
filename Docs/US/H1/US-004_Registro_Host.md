# US-004 — Registro de Usuario Host

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** creador de podcasts (host),
> **quiero** registrarme con email y contraseña,
> **para** tener una cuenta persistente que me permita crear y gestionar salas de grabación.

**Referencia TDD:** §7.2 (Registro), §8 (Seguridad — argon2, rate limiting)
**Prioridad:** P0-Critical
**Estimación total:** XL (3–5 días)
**Dependencias:** US-003

### Criterios de Aceptación

1. `POST /api/auth/register` con `{ email, password }` válidos crea un usuario y retorna `201 Created` con `{ userId, jwt, refreshToken }`.
2. El password se almacena hasheado con argon2 (parámetros: `memoryCost: 65536`, `timeCost: 3`, `parallelism: 4`). El plaintext **nunca** se almacena.
3. Si el email ya existe, retorna `409 Conflict` con mensaje descriptivo.
4. Validación de email: formato válido (regex o class-validator), retorna `400 Bad Request` si no es válido.
5. Validación de password: mínimo 8 caracteres, retorna `400 Bad Request` si no cumple.
6. Rate limiting: máximo 3 registros por IP en 1 hora. Retorna `429 Too Many Requests` si se excede.
7. El JWT generado contiene `{ sub: userId, email, type: "host" }` con expiración de 7 días.
8. El refresh token es un token opaco almacenado en base de datos con expiración de 30 días.
9. La respuesta incluye el refresh token en una cookie `httpOnly`, `secure`, `sameSite: strict`.

### Tareas

#### TASK-008: Implementar AuthModule con estructura base

| Campo | Valor |
|-------|-------|
| **ID** | TASK-008 |
| **Tamaño** | M |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-007 |

**Especificación de implementación:**

1. Crear estructura de módulos:
   ```
   apps/api/src/
   ├── auth/
   │   ├── auth.module.ts
   │   ├── auth.controller.ts
   │   ├── auth.service.ts
   │   ├── auth.service.spec.ts
   │   ├── auth.controller.spec.ts
   │   ├── strategies/
   │   │   ├── local.strategy.ts
   │   │   └── jwt.strategy.ts
   │   ├── guards/
   │   │   ├── jwt-auth.guard.ts
   │   │   └── host.guard.ts
   │   ├── dto/
   │   │   ├── register.dto.ts
   │   │   └── login.dto.ts
   │   └── interfaces/
   │       └── jwt-payload.interface.ts
   └── users/
       ├── users.module.ts
       ├── users.service.ts
       └── users.service.spec.ts
   ```

2. Instalar dependencias:
   ```bash
   pnpm add @nestjs/passport @nestjs/jwt passport passport-local passport-jwt argon2 class-validator class-transformer
   pnpm add -D @types/passport-local @types/passport-jwt
   ```

3. `AuthModule` importa `UsersModule`, `JwtModule`, `PassportModule`.
4. `JwtModule.registerAsync` cargando `JWT_SECRET` y `expiresIn: '7d'` desde `ConfigService`.
5. Habilitar `ValidationPipe` global en `main.ts` con `whitelist: true`, `forbidNonWhitelisted: true`.

**Tests TDD:**
- **Red:** Test que verifica que `AuthModule` se instancia con las dependencias correctas inyectadas.
- **Green:** Configurar el módulo con los imports y providers.

---

#### TASK-009: Implementar UsersService

| Campo | Valor |
|-------|-------|
| **ID** | TASK-009 |
| **Tamaño** | M |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-008 |

**Especificación de implementación:**

1. `UsersService` con los siguientes métodos:
   - `create(email: string, password: string): Promise<User>` — Hashea el password con argon2 y crea el usuario via Prisma. Lanza `ConflictException` si el email ya existe (capturar `PrismaClientKnownRequestError` con código `P2002`).
   - `findByEmail(email: string): Promise<User | null>` — Busca usuario por email.
   - `findById(id: string): Promise<User | null>` — Busca usuario por ID.
   - `validatePassword(plainText: string, hash: string): Promise<boolean>` — Verifica password contra hash con argon2.

2. Parámetros de argon2 según §8 del TDD:
   ```typescript
   import * as argon2 from 'argon2';

   const hash = await argon2.hash(password, {
     type: argon2.argon2id,
     memoryCost: 65536,  // 64 MB
     timeCost: 3,
     parallelism: 4,
   });
   ```

**Tests TDD (unit):**

```typescript
describe('UsersService', () => {
  // Red → Green para cada test:

  it('should create a user with hashed password', async () => {
    const user = await service.create('test@example.com', 'password123');
    expect(user.email).toBe('test@example.com');
    expect(user.passwordHash).not.toBe('password123');
    expect(user.passwordHash).toMatch(/^\$argon2/);
  });

  it('should throw ConflictException on duplicate email', async () => {
    await service.create('test@example.com', 'password123');
    await expect(service.create('test@example.com', 'other'))
      .rejects.toThrow(ConflictException);
  });

  it('should find user by email', async () => {
    await service.create('test@example.com', 'password123');
    const found = await service.findByEmail('test@example.com');
    expect(found).not.toBeNull();
    expect(found.email).toBe('test@example.com');
  });

  it('should return null for non-existent email', async () => {
    const found = await service.findByEmail('noexist@example.com');
    expect(found).toBeNull();
  });

  it('should validate correct password', async () => {
    const user = await service.create('test@example.com', 'password123');
    const valid = await service.validatePassword('password123', user.passwordHash);
    expect(valid).toBe(true);
  });

  it('should reject incorrect password', async () => {
    const user = await service.create('test@example.com', 'password123');
    const valid = await service.validatePassword('wrong', user.passwordHash);
    expect(valid).toBe(false);
  });
});
```

Estos tests requieren una instancia de base de datos (usar testcontainers o una base de test dedicada en Docker Compose).

---

#### TASK-010: Implementar endpoint de registro y DTOs de validación

| Campo | Valor |
|-------|-------|
| **ID** | TASK-010 |
| **Tamaño** | L |
| **Prioridad** | P0-Critical |
| **Dependencias** | TASK-009 |

**Especificación de implementación:**

1. Crear `RegisterDto`:
   ```typescript
   import { IsEmail, IsString, MinLength } from 'class-validator';

   export class RegisterDto {
     @IsEmail()
     email: string;

     @IsString()
     @MinLength(8)
     password: string;
   }
   ```

2. Implementar `AuthService.register(dto: RegisterDto)`:
   - Llamar a `UsersService.create`.
   - Generar JWT con payload `{ sub: user.id, email: user.email, type: 'host' }`.
   - Generar refresh token opaco (`crypto.randomBytes(64).toString('hex')`).
   - Almacenar refresh token hasheado en tabla (ver nota abajo).
   - Retornar `{ userId, jwt, refreshToken }`.

3. **Nota sobre refresh tokens:** Crear tabla Prisma `RefreshToken`:
   ```prisma
   model RefreshToken {
     id        String   @id @default(uuid()) @db.Uuid
     tokenHash String   @map("token_hash") @db.VarChar(255)
     userId    String   @map("user_id") @db.Uuid
     expiresAt DateTime @map("expires_at")
     createdAt DateTime @default(now()) @map("created_at")

     user User @relation(fields: [userId], references: [id], onDelete: Cascade)

     @@map("refresh_tokens")
   }
   ```
   Agregar relación `refreshTokens RefreshToken[]` al modelo `User`. Generar nueva migración.

4. Implementar `AuthController.register`:
   ```typescript
   @Post('register')
   @HttpCode(HttpStatus.CREATED)
   async register(
     @Body() dto: RegisterDto,
     @Res({ passthrough: true }) res: FastifyReply,
   ) {
     const result = await this.authService.register(dto);

     res.setCookie('refresh_token', result.refreshToken, {
       httpOnly: true,
       secure: process.env.NODE_ENV === 'production',
       sameSite: 'strict',
       path: '/api/auth/refresh',
       maxAge: 30 * 24 * 60 * 60, // 30 días en segundos
     });

     return {
       userId: result.userId,
       jwt: result.jwt,
     };
   }
   ```

5. Registrar `@nestjs/config` con `ConfigModule.forRoot({ isGlobal: true })` en `AppModule` para cargar variables de `.env`.

**Tests TDD (integration con Supertest):**

```typescript
describe('POST /api/auth/register', () => {
  it('should register a new user and return JWT', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: 'host@example.com', password: 'securePass123' })
      .expect(201);

    expect(res.body.userId).toBeDefined();
    expect(res.body.jwt).toBeDefined();
    expect(res.headers['set-cookie']).toBeDefined();
    // Verificar que el cookie tiene httpOnly
    const cookie = res.headers['set-cookie'][0];
    expect(cookie).toContain('HttpOnly');
  });

  it('should return 409 for duplicate email', async () => {
    await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: 'dup@example.com', password: 'securePass123' });

    await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: 'dup@example.com', password: 'otherPass456' })
      .expect(409);
  });

  it('should return 400 for invalid email', async () => {
    await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: 'not-an-email', password: 'securePass123' })
      .expect(400);
  });

  it('should return 400 for short password', async () => {
    await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: 'host@example.com', password: 'short' })
      .expect(400);
  });
});
```

---

#### TASK-011: Implementar rate limiting en registro

| Campo | Valor |
|-------|-------|
| **ID** | TASK-011 |
| **Tamaño** | M |
| **Prioridad** | P1-High |
| **Dependencias** | TASK-010 |

**Especificación de implementación:**

1. Instalar `@nestjs/throttler`:
   ```bash
   pnpm add @nestjs/throttler
   ```
2. Registrar `ThrottlerModule.forRoot` en `AppModule` (configuración global por defecto).
3. Aplicar un decorator personalizado en el endpoint de registro con límites específicos (3 requests / 3600 segundos por IP):
   ```typescript
   @Throttle({ default: { limit: 3, ttl: 3600000 } })
   @Post('register')
   ```
4. Configurar `ThrottlerGuard` como guard global o por controller según preferencia.
5. Para Fastify, usar `ThrottlerStorageService` con Dragonfly (Redis-compatible):
   ```bash
   pnpm add @nestjs/throttler-storage-redis ioredis
   ```
   Configurar con URL de Dragonfly.

**Tests TDD:**

```typescript
it('should return 429 after 3 registration attempts from same IP', async () => {
  for (let i = 0; i < 3; i++) {
    await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ email: `user${i}@example.com`, password: 'securePass123' })
      .expect(201);
  }

  await request(app.getHttpServer())
    .post('/api/auth/register')
    .send({ email: 'user4@example.com', password: 'securePass123' })
    .expect(429);
});
```
