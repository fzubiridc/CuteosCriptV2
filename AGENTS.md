# AGENTS.md — punto de entrada para agentes/devs

Juego **Godot 4.6** isométrico 2D tipo Diablo-like / dungeon-crawler. Rama de trabajo: **`iso-merge`**.
Port a Godot del original en Pixi (el pixi es legacy; este proyecto ya va por delante).

## Leé esto antes de tocar (en orden)
1. **`docs/project_memory.md`** — estado confirmado, decisiones tomadas, fixes que NO revertir, lista "no tocar". (Actualizado al 2026-06-27.)
2. **`docs/architecture_notes.md`** — cómo funciona cada sistema (escena, dungeon y sus módulos, muros, niebla, luz, IA, audio, FX). (Actualizado al 2026-06-27.)
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
- Arranque = **`scenes/menu.tscn`** (menú de inicio: título + tarjeta animada del Archimago + récords/continuar; al jugar hace `change_scene_to_file` a `main.tscn`). Escena de juego = **`scenes/main.tscn`**; `ISO=true` es el único path vivo; `Dungeon.use_test_map` debe quedar en **false**.
- **No tocar `addons/godot_ai/`** (vendor/plugin).
- **Commits/push: solo cuando Felipe lo pide** (no por iniciativa propia).
- **Validación:** Felipe prueba jugando (más rápido). Los agentes validan con **compile-check headless** (`godot --headless --path . --import`, exit 0 + sin `SCRIPT ERROR`/`Parse Error`); **no abrir el juego ni screenshotear** salvo que Felipe lo pida.
- Iluminación / antorchas / visibilidad / procgen / player / enemigos / HUD son **sensibles**: cambios incrementales + test visual.
- **Oscuridad = ausencia de luz** (no overlay). El fog NO apaga caras de muro visibles desde el cuarto activo.
- **Muros = `WallSegment`** (fuente lógica): NW/NE traseros, SE/SW fachada; `neighbor()` depende de la **paridad de fila** (TileSet STACKED). Salas = **paralelogramos** (`carve_iso_room`), no rects cartesianos.
- Refactor de un módulo grande → mové la lógica preservando la API pública (otros archivos dependen de `dungeon.*`, etc.) y dejá un wrapper.

## Protocolo de cierre (Definition of Done)
Al cerrar cualquier tarea que cambie código del juego (`scripts/`, `scenes/`, `shaders/`, `project.godot`):
1. Mirá el `git status` real de lo que tocaste.
2. Cambió el **estado** del juego (feature, sistema, bug vivo, deuda saldada) → actualizá `docs/project_memory.md` y el bloque **"Estado en una línea"** de abajo.
3. Cambió **cómo funciona** un sistema (no solo qué hace) → actualizá `docs/architecture_notes.md`.
4. Decisión tomada o revertida → anotala en `docs/project_memory.md` (decisiones / "no tocar").
5. **Convención de nombres:** los docs vivos van **sin fecha** (`project_memory.md`, `architecture_notes.md`) — editá el archivo vivo, nunca crees una copia fechada. Solo los snapshots históricos llevan fecha (`code_audit_2026-06-26.md`, `cleanup_candidates_2026-06-26.md`) y no se actualizan.

Si el cambio es trivial o no altera nada documentado, **decilo en una línea y cerrá** — no inventes updates ni marques como hecho lo que no está en el repo. Un Stop hook (`.claude/hooks/check-memory.mjs`) te recuerda esto si tocás código sin tocar `docs/`.

## Estado en una línea
**Sesión 2026-06-29.quater (sin commitear):** (1) **fix bug histórico del rig del player**: el `z_index` de los hijos del `Rig` (CanvasGroup) se FUGABA al mundo → en `idle_north`/`walk_north` (z=5) y `walk_east/west` (z=3) el cuerpo+vara+mano se dibujaban sobre muros/props y cambiaba la calidez del cuerpo (perdía el tinte de luz del pie). Fix: todos los `Body:z_index` de `mage_anims.tres` → 0 (con `.bak`), y el apilado cuerpo↔vara ahora por **orden de árbol** (`player._set_body_front` con `rig.move_child`), todo el rig en z 0 → aplana atómico. Ver `architecture_notes.md §5`. (2) **Sandbox `scenes/props_test.tscn`** (+ `props_test.gd`): cuarto cerrado con props a mano para probar oclusión; usa `DungeonProps.spawn_at` (público). (3) Props **cuelgan de Main** (mismo y_sort que el player) → te tapan OPACOS si estás detrás; sin cutaway de props; default escala `384/w` y `props.json` viejo subido ×3. (4) **OCLUSIÓN X-AWARE por HUELLA** (Felipe: "AHHH FINALMENTE"): estás detrás del prop si, a tu columna X, la huella se extiende al sur de tus pies (sigue el borde inclinado iso; un escalar único sobre-tapaba por el costado). Por-frame: `DungeonProps.update_occlusion`/`_player_behind` setea el `z_index` del prop arriba/abajo del player; huella guardada en world al spawn; props sin huella → y_sort estático (`ysort` manual). Patrón reusable (memoria `reference_iso_ysort_footprint`). Detalle en `architecture_notes.md §1.props/§5`.

**Sesión 2026-06-29.ter (sin commitear):** (1) **minimapa → AUTOMAP estilo Diablo II**: wireframe iso de líneas (no relleno) — `minimap.gd` reescrito + nuevo `minimap_wire.gd` (`MinimapWire`), aristas de `Dungeon.get_wall_edges()`, radar circular + mapa M overlay translúcido. (2) Dos REGLAS nuevas de divisores en `dungeon_dividers.gd`: **ninguna región sin salida** (`ensure_connectivity`: flood-fill desde spawn, abre hueco en regiones selladas) + **sin puertas encimadas con muros** (`resolve_overlaps`: reubica la puerta a celda limpia; el render comparte el muro perimetral). Pipeline `_place_dividers` = plan → resolve_overlaps → ensure_connectivity → render. Compila headless OK (exit 0); falta que Felipe lo pruebe. Detalle en `docs/project_memory.md §7.ter` + `architecture_notes.md §3.bis/§3.ter`.

**Sesión 2026-06-29.bis (sin commitear):** **sistema de PROPS iso**. (1) Importado pack **Kenney Isometric** (144 PNGs, 4 facings E/N/S/W) a `assets/iso/props/kenney/`. (2) Tab web nueva **📦 Props** (`tools/props_tool.html`): seleccionás un asset y le fijás escala, anclaje (centro o borde de muro NW/NE/SE/SW + offset arrastrable), polígono de colisión (cell-local, igual que muros), weight y enabled → auto-guarda en `tools/rig/props.json` vía `GET/POST /api/props` (serve.py). Auto-descubre toda imagen de `assets/iso/props/**` (assets futuros aparecen solos). (3) Autoload **PropCatalog** + módulo **DungeonProps** (`place_props` en `generate()`) esparce props ponderados por el piso con anclaje + colisión + bloqueo de nav. Scripts parsean OK (find_symbols limpio); **falta** reimport de los PNGs (el editor estaba en play) y que Felipe lo pruebe. (4) **Posicionamiento z (final):** los props son **objetos sólidos** colgados de **`Main`** (mismo y_sort que el player) → el motor los ordena por profundidad contra el player: te parás detrás de una mesa/biblioteca y te **tapa opaca** (sin transparentar), adelante la tapás vos. Trade-off: player y muros no comparten y_sort → el prop y-sortea con el player (que te tape) y queda en bucket grueso vs muros (ok para muebles en pared). **NO** hay cutaway de props. Sprite + colisión ×`gs`(0.5) para calzar con tiles. Default de escala `384/w` (~1.5× tile); **`props.json` viejo tenía todo en 0.5 → subido ×3 a 1.5** (anclajes/colisiones preservados). Solo Kenney importado (Hand-Drawn descartado). Detalle en `docs/architecture_notes.md §1.props`.

**Sesión 2026-06-29 (sin commitear):** procgen — (1) **corredores isométricos**: `dungeon_gen._connect` talla la L por los ejes visuales del rombo (SE/SW) en vez de `carve_h`/`carve_v` cartesianos (escalera dentada); (2) **divisores que siempre topan muro**: `dungeon_dividers.add_divider` crece desde el centro hasta toparse vacío/borde en ambos extremos → no más divisores flotando en la nada. Compila headless OK (Godot 4.6.3, exit 0). Felipe verificó jugando ("perfecto ambos"). Detalle en `docs/project_memory.md §7.ter/§7.quater`.

**Sesión 2026-06-28 (autónoma, sin commitear):** fix crash ESC (audio.gd), fix luz de mobs inconsistente (cull por proximidad en `light_field.pack_lights`), luz del jugador con perímetro difuso (gaussiana en `player._apply_light_tex`), **minimapa centrado en el jugador** (radar con AtlasTexture en `minimap.gd`), **barra de habilidades RPG nueva** (`ability_defs.gd` + `ui/skill_bar.gd` + slots/cooldowns en `player.gd`, teclas 1-4 + K, AoE migró de E al slot 1), impacto de fuego rotado a la dirección (`projectile.gd`), XP bar 16px más abajo, botón debug de regen removido, clear color oscuro (mata el gris post-intro). Detalle + dudas abiertas en `docs/project_memory.md §7.bis`. Compila headless OK; falta que Felipe lo pruebe jugando.

Juego iso funcional y pulido, todo en `iso-merge`. `dungeon.gd` partido en **gen/decor/fog**, `hud` en paneles, **CombatDirector** autoload, mercader desacoplado por señal. Features recientes: **audio inmersivo** (buses+reverb+SFX posicional), **bolt de fuego por vara**, **FX de combate** (burn, números de daño, fogatas, luz propia de mobs), **boot splash**, **aura propia del boss** (se ve en la oscuridad), **FX de hechizos data-driven** (tab web ✨Hechizos `tools/spell_tool.html` → `tools/rig/spells.json` → `SpellLibrary`→`ElementProfile`→`SpellFX` por vara, modo `external` que aumenta el bolt existente sin pisar el arte; WYSIWYG, ver `docs/spell_fx_plan.md`). Deuda viva: nav marca piso-con-muro sólido, `place_torches` asume salas cartesianas, el boss nunca se oculta, sandboxes sin mover, tilesets `iso_dungeon_v*` chatarra. Ver `docs/`.
