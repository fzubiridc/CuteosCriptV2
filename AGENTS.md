# AGENTS.md — punto de entrada para agentes/devs

Juego **Godot 4.6** isométrico 2D tipo Diablo-like / dungeon-crawler. Rama de trabajo: **`iso-merge`**.
Port a Godot del original en Pixi (el pixi es legacy; este proyecto ya va por delante).

## Leé esto antes de tocar (en orden)
1. **`docs/project_memory_2026-06-26.md`** — estado confirmado, decisiones tomadas, fixes que NO revertir, lista "no tocar". (Actualizado al 2026-06-27.)
2. **`docs/architecture_notes_2026-06-26.md`** — cómo funciona cada sistema (escena, dungeon y sus módulos, muros, niebla, luz, IA, audio, FX). (Actualizado al 2026-06-27.)
3. Planes puntuales (algunos parcialmente implementados): `docs/spell_fx_plan.md`, `docs/visibility_darkness_plan.md`, `docs/PLAN_NARRATIVO.md`, `docs/lore/`.

> `docs/code_audit_2026-06-26.md` y `docs/cleanup_candidates_2026-06-26.md` son **snapshots de la revisión del 26-jun**, históricos: su deuda principal (god-objects `dungeon.gd`/`hud.gd`, path 2.5D muerto, director static) **ya se resolvió**. No los leas como estado actual.

## Mapa rápido del código
- **`scripts/`** — lógica. Núcleo: `main.gd` (flujo de pisos), `player.gd`, `enemy.gd`, `boss.gd`, `projectile.gd`, `hud.gd`.
- **`scripts/dungeon.gd`** — el nodo del piso: RENDER iso (piso/muros/occluders/variantes/puertas) + nav (AStarGrid) + API pública + orquesta `generate()`. **Partido en 3 módulos** `RefCounted` que operan sobre él (`d.*`, creados lazy):
  - `scripts/dungeon_gen.gd` (**DungeonGen**) — procgen: grid, salas iso (paralelogramos), grafo MST+loops, roles, spawn/exit, puertas.
  - `scripts/dungeon_decor.gd` (**DungeonDecor**) — antorchas + fogatas.
  - `scripts/dungeon_fog.gd` (**DungeonFog**) — niebla de guerra + reveal de fachadas.
  - Estado compartido que vive en `dungeon.gd` (lo leen render/minimap/enemy/manager): `grid`, `rooms`, `cell_seen`, `_room_of`, `_room_front`, `_front_src`.
- **`scripts/ui/`** — `shop_panel.gd` (ShopPanel) + `inventory_panel.gd` (InventoryPanel); `hud.gd` los coordina.
- **`scripts/autoload/`** — `rng`, `game_state`, `data`, `items`, `audio`, `light_cfg`, `light_field`, `fx_materials`, `save_system`, `fps_counter`, **`combat_director`** (tope de atacantes simultáneos). Registrados en `project.godot [autoload]`.
- **`scenes/`** — `main.tscn` (la de producción), `player`, `enemy`, `boss`, `projectile`, `pickup`, `floater`, `campfire`, `menu`, + sandboxes (`closed_room_test`, `iso_test`, `light_test`).
- **`shaders/`** — `wall_face.gdshader` (caras de muro + entidades, foot-lit unshaded).
- **`tools/`** — tooling web propio. Server único `py tools/serve.py` (puerto 8765, auto-guarda) + `rigtool.html` (rig de varas/anims/bolts + escala) + `rig_sync.py` (converter → `data.gd`) + `aoe_glyph_tool.html` + `index.html` (tabs). El pixi se sirve en `/pixi/`.
- **`assets/`** — tiles iso, fx, sfx, hero/staffs, mobs, ui (incluye `ui/loading.png` = boot splash), `story/` (intro narrativa, pendiente).

## Reglas duras
- Main scene = **`scenes/main.tscn`**; `ISO=true` es el único path vivo; `Dungeon.use_test_map` debe quedar en **false**.
- **No tocar `addons/godot_ai/`** (vendor/plugin).
- **Commits/push: solo cuando Felipe lo pide** (no por iniciativa propia).
- **Validación:** Felipe prueba jugando (más rápido). Los agentes validan con **compile-check headless** (`godot --headless --path . --import`, exit 0 + sin `SCRIPT ERROR`/`Parse Error`); **no abrir el juego ni screenshotear** salvo que Felipe lo pida.
- Iluminación / antorchas / visibilidad / procgen / player / enemigos / HUD son **sensibles**: cambios incrementales + test visual.
- **Oscuridad = ausencia de luz** (no overlay). El fog NO apaga caras de muro visibles desde el cuarto activo.
- **Muros = `WallSegment`** (fuente lógica): NW/NE traseros, SE/SW fachada; `neighbor()` depende de la **paridad de fila** (TileSet STACKED). Salas = **paralelogramos** (`carve_iso_room`), no rects cartesianos.
- Refactor de un módulo grande → mové la lógica preservando la API pública (otros archivos dependen de `dungeon.*`, etc.) y dejá un wrapper.

## Estado en una línea
Juego iso funcional y pulido, todo en `iso-merge`. `dungeon.gd` partido en **gen/decor/fog**, `hud` en paneles, **CombatDirector** autoload, mercader desacoplado por señal. Features recientes: **audio inmersivo** (buses+reverb+SFX posicional), **bolt de fuego por vara**, **FX de combate** (burn, números de daño, fogatas, luz propia de mobs), **boot splash**. Deuda viva: nav marca piso-con-muro sólido, `place_torches` asume salas cartesianas, el boss nunca se oculta, sandboxes sin mover, tilesets `iso_dungeon_v*` chatarra. Ver `docs/`.
