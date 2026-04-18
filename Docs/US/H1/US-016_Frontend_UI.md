# US-016 — Interfaz de Usuario Mínima (Frontend)

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** usuario (host o guest),
> **quiero** una interfaz web básica con pantallas de registro/login, creación de sala, unión a sala y panel de participantes,
> **para** poder usar la plataforma de forma visual e intuitiva.

**Referencia TDD:** §6.1.3 (Interfaz de Usuario), §11.1
**Prioridad:** P1-High
**Estimación total:** XL (3–5 días)
**Dependencias:** US-013, US-014

### Criterios de Aceptación

1. Existe una pantalla de registro con formulario de email y contraseña.
2. Existe una pantalla de login con formulario de email y contraseña.
3. Tras login exitoso, el host ve un dashboard con botón "Crear sala" y listado de sus salas.
4. Al crear una sala, se muestra el código de invitación y un enlace copiable.
5. Existe una pantalla de "Unirse a sala" donde el guest introduce código de invitación, nombre y email opcional.
6. Dentro de la sala, se muestra un panel con los avatares/nombres de todos los participantes conectados.
7. El indicador de estado muestra: conectando, en sala, desconectado.
8. El botón de muteo está visible y funcional.
9. La navegación usa React Router (o similar) con rutas protegidas para hosts.

### Tareas

#### TASK-027: Implementar pantallas de autenticación (Register / Login)

| Campo | Valor |
|-------|-------|
| **ID** | TASK-027 |
| **Tamaño** | L |
| **Prioridad** | P1-High |
| **Dependencias** | TASK-010, TASK-012, TASK-003 |

**Especificación de implementación:**

1. Instalar React Router:
   ```bash
   pnpm add react-router-dom
   ```

2. Crear estructura de páginas:
   ```
   apps/web/src/
   ├── pages/
   │   ├── RegisterPage.tsx
   │   ├── LoginPage.tsx
   │   ├── DashboardPage.tsx
   │   ├── JoinRoomPage.tsx
   │   └── RoomPage.tsx
   ├── components/
   │   ├── AuthForm.tsx
   │   ├── ParticipantPanel.tsx
   │   ├── MuteButton.tsx
   │   └── Layout.tsx
   ├── hooks/
   │   ├── useAuth.ts
   │   ├── useWebSocket.ts
   │   └── useMediasoup.ts
   ├── services/
   │   └── api.ts
   └── contexts/
       └── AuthContext.tsx
   ```

3. Implementar `AuthContext` para gestionar JWT en memoria:
   ```typescript
   const AuthContext = createContext<{
     jwt: string | null;
     user: { userId: string; email: string } | null;
     login: (email: string, password: string) => Promise<void>;
     register: (email: string, password: string) => Promise<void>;
     logout: () => void;
   }>(null);
   ```

4. Implementar `RegisterPage` y `LoginPage` con formularios y validación client-side.

5. Implementar servicio `api.ts` con funciones para cada endpoint:
   ```typescript
   export const api = {
     register: (email: string, password: string) =>
       fetch('/api/auth/register', { method: 'POST', ... }),
     login: (email: string, password: string) =>
       fetch('/api/auth/login', { method: 'POST', ... }),
     // etc.
   };
   ```

6. Implementar rutas protegidas:
   ```tsx
   function ProtectedRoute({ children }: { children: ReactNode }) {
     const { jwt } = useAuth();
     if (!jwt) return <Navigate to="/login" />;
     return children;
   }
   ```

**Tests TDD:**

```typescript
describe('RegisterPage', () => {
  it('should render email and password fields', () => {
    render(<RegisterPage />);
    expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/password/i)).toBeInTheDocument();
  });

  it('should show validation error for short password', async () => {
    render(<RegisterPage />);
    await userEvent.type(screen.getByLabelText(/password/i), 'short');
    await userEvent.click(screen.getByRole('button', { name: /registrar/i }));
    expect(screen.getByText(/mínimo 8 caracteres/i)).toBeInTheDocument();
  });
});
```

---

#### TASK-028: Implementar dashboard del host y pantalla de sala

| Campo | Valor |
|-------|-------|
| **ID** | TASK-028 |
| **Tamaño** | L |
| **Prioridad** | P1-High |
| **Dependencias** | TASK-027 |

**Especificación de implementación:**

1. **DashboardPage:**
   - Listar salas del host (`GET /api/rooms`).
   - Botón "Crear sala" que llama a `POST /api/rooms` y muestra el resultado.
   - Cada sala muestra: código, estado, fecha de creación, participantes.
   - Click en una sala navega a `RoomPage`.

2. **JoinRoomPage (para guests):**
   - Formulario con: código de sala, nombre, email (opcional).
   - Al enviar, llama a `GET /api/rooms/:code` para verificar y luego `POST /api/rooms/:id/join`.
   - Al obtener JWT, navegar a `RoomPage`.

3. **RoomPage:**
   - Conectar WebSocket y enviar `room:join` con JWT.
   - Iniciar mediasoup y comenzar a producir/consumir audio.
   - Mostrar `ParticipantPanel` con lista de participantes y su estado.
   - Mostrar `MuteButton`.
   - Mostrar indicador de estado de conexión.

4. **ParticipantPanel:**
   ```tsx
   function ParticipantPanel({ participants }: { participants: ParticipantInfo[] }) {
     return (
       <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-5">
         {participants.map(p => (
           <div key={p.id} className="flex flex-col items-center gap-2">
             <div className="h-16 w-16 rounded-full bg-gray-200 flex items-center justify-center text-2xl">
               {p.displayName[0].toUpperCase()}
             </div>
             <span className="text-sm">{p.displayName}</span>
             <span className="text-xs text-gray-500">{p.status}</span>
           </div>
         ))}
       </div>
     );
   }
   ```

**Tests TDD:**

```typescript
describe('ParticipantPanel', () => {
  it('should render all participants', () => {
    const participants = [
      { id: '1', displayName: 'Alice', role: 'host', status: 'connected' },
      { id: '2', displayName: 'Bob', role: 'guest', status: 'connected' },
    ];
    render(<ParticipantPanel participants={participants} />);
    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.getByText('Bob')).toBeInTheDocument();
  });
});

describe('DashboardPage', () => {
  it('should show create room button', () => {
    render(<DashboardPage />);
    expect(screen.getByRole('button', { name: /crear sala/i })).toBeInTheDocument();
  });
});
```
