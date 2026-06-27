# AGENTS.md — punto de entrada para agentes/devs

Juego Godot 4.6 isométrico 2D tipo Diablo-like / dungeon-crawler. Rama `iso-merge`.

## Leé esto antes de tocar (en orden)
1. **`docs/project_memory_2026-06-26.md`** — estado confirmado, decisiones, fixes que NO revertir, lista "no tocar".
2. **`docs/code_audit_2026-06-26.md`** — riesgos, bugs sospechosos, recomendaciones priorizadas.
3. **`docs/architecture_notes_2026-06-26.md`** — cómo funciona cada sistema (escena, dungeon, muros, fog, luz, IA).
4. **`docs/cleanup_candidates_2026-06-26.md`** — qué se puede borrar (con evidencia; nada borrado aún).
5. **`docs/visibility_darkness_plan.md`** — plan de oscuridad/fog (ojo: tiene partes desactualizadas vs el código).

> ⚠ El `README.md` describe el render como "2.5D" — **desactualizado**: el path vivo es **iso** (`ISO=true`).

## Reglas duras
- Main scene = `scenes/main.tscn`; `Dungeon.use_test_map` debe quedar en **false**.
- No tocar `addons/godot_ai/` (vendor). No commits/push (los hace Felipe).
- Iluminación/antorchas/visibilidad/procgen/player/enemigos/HUD son **sensibles**: cambios incrementales + test visual.
- Oscuridad = ausencia de luz (no overlay). El fog NO apaga caras de muro visibles desde el cuarto activo.
- Muros = `WallSegment` (fuente lógica). NW/NE traseros, SE/SW fachada.

## Estado en una línea
Migración reciente (esta sesión, sin commitear): oscuridad estilo D2 + puertas-teleport (`USE_DOORS`) +
IA de mobs (FSM windup/recovery + slots + director) + luz propia de mobs + knobs de gradiente. Funciona;
deuda principal = `dungeon.gd`/`hud.gd` god-objects + path 2.5D muerto + sandbox sin mover. Ver auditoría.
