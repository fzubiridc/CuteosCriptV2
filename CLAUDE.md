@AGENTS.md

## Mantenimiento de memoria (Claude Code)

El **Protocolo de cierre** de `AGENTS.md` es parte del Definition of Done: al terminar una tarea que cambia codigo del juego, actualiza los `docs/` que correspondan en la misma tarea.

Un Stop hook (`.claude/hooks/check-memory.mjs`) te lo recuerda **automaticamente** cuando tocaste `scripts/`, `scenes/`, `shaders/` o `project.godot` sin tocar `docs/`. No bloquea: lee el recordatorio y actualiza lo que corresponda, o explica en una linea por que no aplica.
