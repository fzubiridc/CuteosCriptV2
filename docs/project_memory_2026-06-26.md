# Memoria del proyecto — 2026-06-26 (para agentes/devs futuros)

> Leé esto PRIMERO antes de tocar nada. Evita repetir diagnósticos viejos y revertir fixes.
> Complementos: `code_audit_2026-06-26.md`, `architecture_notes_2026-06-26.md`,
> `cleanup_candidates_2026-06-26.md`, `visibility_darkness_plan.md`.

## 1. Estado actual confirmado
- **Godot 4.6**, juego isométrico 2D tipo Diablo-like / dungeon-crawler. Rama `iso-merge`.
- Main scene = **`scenes/main.tscn`**; `Dungeon.use_test_map` debe quedar en **false** en producción.
- Procgen **iso ACTIVO** (`dungeon.gd`, `ISO=true`). Modo **USE_DOORS=true**: salas cerradas + puertas-teleport (banco de pruebas de la oscuridad).
- Muros = **`WallSegment`** (fuente lógica). **NW/NE = traseros**, **SE/SW = delanteros/fachada**. Capas `IsoWalls` (z+1) / `IsoWallsBack` (z-1). `neighbor()` depende de **paridad de fila** (TileSet STACKED).
- TileSet vivo = **`assets/iso/iso_pixel.tres`** (los `iso_dungeon_v*` son chatarra).
- Iluminación/antorchas/occluders **sensibles**: no tocar sin test visual. Knobs en `LightCfg` (tecla L, persiste en `user://light_knobs.json`).
- Visibilidad/fog **en transición**: oscuridad por luz real + grilla `cell_seen`/`_visible_now` en Dungeon (fuente de verdad), minimapa y manager la consumen. NO hay overlay fullscreen oscurecedor.
- HUD/inventario/tienda/vida/maná/XP/jefe viven todos en `hud.gd` (god-object).

## 2. Decisiones de diseño tomadas (no reabrir sin motivo)
- **Muros bajos: descartado.** Muro que tapa al player → **transparencia/reveal de fachada**, NO borrar muros.
- **Oscuridad = ausencia de luz** (no un velo/overlay). **Explorado = recordado** (minimapa), no iluminado para siempre. Estilo Diablo 2.
- 3 estados de visibilidad: **visible ahora / explorado-recordado / no visto.** Las caras de muro visibles desde el cuarto activo **NO** se oscurecen por limitar con un cuarto no visitado.
- Player rig = **CanvasGroup** (atómico contra muros) — decisión buena.
- IA de mobs: por ahora caminata + ataque con **windup/recovery + slots + director (máx 3) + histéresis**. No planear IA compleja sin afinar esto primero.
- Cámara: **player fijo al centro, el mapa se desliza** (Camera2D hija, `make_current`).

## 3. Fixes importantes que NO deben revertirse
- `main.tscn`: `use_test_map = false` (el bug "regen da mismo mapa" era el test map activo, **no** el seed/RNG).
- `WallSegment.neighbor()` por **paridad de fila** (no DIR fijo) — resolvió el serrucho de muros.
- Migración de oscuridad: overlay `room_darkness.gd` **borrado** a propósito (era BG3, no D2). No re-agregar un velo por-sala.
- Minimapa **lee** `dungeon.cell_seen` (Dungeon es la fuente de verdad, no la UI).
- Antorchas: anclaje por **borde/cara de muro** iso, no por celda top-down vieja (`spawn_wall_torch`). (El `_place_torches` del procgen real todavía es cartesiano — bug pendiente, NO es un fix a revertir.)
- Variantes de muro: se registran como **sources del TileSet en runtime** (`_ensure_wall_variants`), reusan origins base. No hardcodear en el `.tres`.

## 4. Trabajo en transición (esperá inconsistencias acá)
- Sistema de oscuridad/visibilidad: funciona pero el gating de **mobs es por distancia (disco)**, no por celda/LOS; la rama `vis_threat` del manager quedó muerta; el **boss nunca se oculta**. `visibility_darkness_plan.md` describe parte del comportamiento viejo. Unificar a futuro.
- `dungeon.gd` (1875 líneas) y `hud.gd` (739): god-objects a partir (propuesta en `architecture_notes`).
- Path **2.5D muerto** dentro de `dungeon.gd` (~600 líneas) conviviendo con el iso.
- Escenas/scripts **sandbox** sin mover (`iso_test`, `closed_room_test`, `light_test` + sus scripts).
- Posible limpieza de tilesets `iso_dungeon_v*` y assets iso viejos.

## 5. Lista "NO TOCAR sin permiso de Felipe"
- Reescritura grande de procgen / lighting / player / dungeon.
- Cambio global de iluminación; cambio de arte/tilesets; borrado de assets grandes.
- Cambios fuertes de save/load o de balance de enemigos.
- `addons/godot_ai/` (vendor/plugin).
- Implementar un sistema de fog/IA nuevo completo.
- Commits/push (los hace Felipe).

## 6. Qué leer primero un agente nuevo
1. Este archivo. 2. `code_audit_2026-06-26.md` (riesgos + recomendaciones). 3. `architecture_notes_2026-06-26.md`
(cómo funciona cada sistema). 4. `visibility_darkness_plan.md` (oscuridad/fog, ojo que tiene partes viejas).
5. Para arrancar: validar el caso A→B de oscuridad y el feel de combate; después el bug de nav.
