# US-017 — Seed de Desarrollo

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** desarrollador,
> **quiero** tener un comando de seed que cree un usuario de prueba,
> **para** poder probar el sistema rápidamente sin pasar por el flujo de registro manualmente.

**Referencia TDD:** §11.1 ("Seed de desarrollo: comando `pnpm seed:admin`")
**Prioridad:** P2-Medium
**Estimación total:** S (< 4h)
**Dependencias:** US-004

### Criterios de Aceptación

1. `pnpm seed:admin` crea un usuario con email `admin@podsync.dev` y password `admin123456` (o valores configurables por env).
2. Si el usuario ya existe, no falla — imprime mensaje indicando que ya existe.
3. El script usa Prisma Client directamente.
4. Las credenciales por defecto están documentadas en el README.

### Tareas

#### TASK-029: Crear script de seed para usuario administrador

| Campo | Valor |
|-------|-------|
| **ID** | TASK-029 |
| **Tamaño** | S |
| **Prioridad** | P2-Medium |
| **Dependencias** | TASK-009 |

**Especificación de implementación:**

1. Crear `apps/api/prisma/seed.ts`:
   ```typescript
   import { PrismaClient } from '@prisma/client';
   import * as argon2 from 'argon2';

   const prisma = new PrismaClient();

   async function main() {
     const email = process.env.SEED_ADMIN_EMAIL ?? 'admin@podsync.dev';
     const password = process.env.SEED_ADMIN_PASSWORD ?? 'admin123456';

     const existing = await prisma.user.findUnique({ where: { email } });
     if (existing) {
       console.log(`User ${email} already exists, skipping.`);
       return;
     }

     const passwordHash = await argon2.hash(password, {
       type: argon2.argon2id,
       memoryCost: 65536,
       timeCost: 3,
       parallelism: 4,
     });

     const user = await prisma.user.create({
       data: { email, passwordHash },
     });

     console.log(`Created admin user: ${user.email} (${user.id})`);
   }

   main()
     .catch(console.error)
     .finally(() => prisma.$disconnect());
   ```

2. Agregar script en `apps/api/package.json`:
   ```json
   { "seed:admin": "tsx prisma/seed.ts" }
   ```

3. Agregar script en `package.json` raíz:
   ```json
   { "seed:admin": "pnpm --filter api seed:admin" }
   ```

**Verificación:** `pnpm seed:admin` crea el usuario. Ejecutar de nuevo no falla. Login con `admin@podsync.dev` / `admin123456` retorna JWT.
