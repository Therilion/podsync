# US-014 — Muteo y Desmuteo de Micrófono

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** participante,
> **quiero** poder silenciar y activar mi micrófono con un botón,
> **para** evitar que los demás escuchen ruido de fondo cuando no estoy hablando.

**Referencia TDD:** §6.1.3 (Botón Mutear/Desmutear), RF-08
**Prioridad:** P1-High
**Estimación total:** M (4–8h)
**Dependencias:** US-013

### Criterios de Aceptación

1. El botón toggle alterna entre mutear y desmutear el micrófono.
2. Al mutear: el track de audio del Producer de mediasoup se pausa (`producer.pause()`).
3. Al desmutear: el track se reanuda (`producer.resume()`).
4. El estado de mute se comunica visualmente (icono de micrófono tachado).
5. Los demás participantes ven un indicador visual de que el participante está muteado.
6. El mute/unmute no afecta la conexión WebSocket ni la sesión.

### Tareas

#### TASK-025: Implementar toggle de muteo en frontend y señalización

| Campo | Valor |
|-------|-------|
| **ID** | TASK-025 |
| **Tamaño** | M |
| **Prioridad** | P1-High |
| **Dependencias** | TASK-024 |

**Especificación de implementación:**

1. Agregar estado `isMuted` al hook de mediasoup o al state de la sala.
2. Al mutear:
   ```typescript
   producer.pause();
   track.enabled = false;
   ws.send({ event: 'media:producer-paused', data: { roomId } });
   ```
3. Al desmutear:
   ```typescript
   producer.resume();
   track.enabled = true;
   ws.send({ event: 'media:producer-resumed', data: { roomId } });
   ```
4. En el backend, agregar handlers que reenvíen el evento a los demás participantes.
5. En el frontend, mostrar indicador de mute en el panel de participantes basado en los eventos recibidos.

6. Crear componente `MuteButton`:
   ```tsx
   function MuteButton({ isMuted, onToggle }: { isMuted: boolean; onToggle: () => void }) {
     return (
       <button onClick={onToggle} aria-label={isMuted ? 'Activar micrófono' : 'Silenciar micrófono'}>
         {isMuted ? <MicOffIcon /> : <MicOnIcon />}
       </button>
     );
   }
   ```

**Tests TDD:**

```typescript
describe('MuteButton', () => {
  it('should render mic-on icon when not muted', () => {
    render(<MuteButton isMuted={false} onToggle={() => {}} />);
    expect(screen.getByLabelText('Silenciar micrófono')).toBeInTheDocument();
  });

  it('should render mic-off icon when muted', () => {
    render(<MuteButton isMuted={true} onToggle={() => {}} />);
    expect(screen.getByLabelText('Activar micrófono')).toBeInTheDocument();
  });

  it('should call onToggle when clicked', async () => {
    const onToggle = jest.fn();
    render(<MuteButton isMuted={false} onToggle={onToggle} />);
    await userEvent.click(screen.getByRole('button'));
    expect(onToggle).toHaveBeenCalledTimes(1);
  });
});
```
