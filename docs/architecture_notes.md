# Notas de arquitectura — actualizado 2026-06-27

Mapa de los sistemas reales del juego (path vivo: iso, `ISO=true`). Godot 4.6, rama `iso-merge`.
Para deuda/cleanup ver `code_audit_2026-06-26.md` y `cleanup_candidates_2026-06-26.md`.

> **Cambio grande desde la versión anterior del doc**: `dungeon.gd` y `hud.gd` eran god-objects;
> se PARTIERON. El path 2.5D/Tiled muerto se removió. El director de combate pasó a autoload.
> Se sumaron sistemas nuevos: AUDIO posicional, PROYECTIL/bolt por vara, y FX de combate
> (quemado, números de daño, AoE, fogatas). Detalle en cada sección.

## Árbol de escena (producción — `scenes/main.tscn`)
```
Main (Node2D, y_sort)              scripts/main.gd  — flujo: _build_floor, spawns, save/load, exit
├── Dungeon (TileMapLayer)         scripts/dungeon.gd — RENDER iso + orquesta gen/decor/fog (ver §1)
│   ├── IsoWalls (TileMapLayer z=+1)      fachada delantera SE/SW (tapa al player) + reveal
│   ├── IsoWallsBack (TileMapLayer z=-1)  muros traseros NW/NE (el player los tapa)
│   └── (StaticBody2D de perímetro)       _iso_bounds — colisión en el borde del piso (rombos)
├── Player (CharacterBody2D)       scripts/player.gd  (instancia de scenes/player.tscn)
│   ├── Shape / Feet (Marker2D)
│   ├── Camera2D (zoom, sigue al player → player centrado, mapa se desliza)
│   │   └── Motes (GPUParticles2D)
│   ├── Rig (CanvasGroup)          ← composita Body+Hand/Weapon(+Tip)+HandOverlay+StaffArm ATÓMICO contra muros
│   ├── AnimationPlayer
│   └── Light (PointLight2D)       ← charco del player (con height ~24 → se autoilumina el sprite)
├── HUD (CanvasLayer)              scripts/hud.gd — vida/maná/XP/jefe/upgrade/pausa/muerte (ver §7)
│   ├── BossUI / XPBar / LifeManaPreview / StatsLabel / DashCooldown
│   ├── UpgradePanel / PausePanel / DeathPanel
│   └── InventoryPanel             ← el InventoryPanel CONTROLADOR (scripts/ui/) construye DENTRO de este nodo
├── Ambient (CanvasModulate)       ← lo pisa LightCfg.ambient_color() vía lighting_debug
├── Env (WorldEnvironment)
├── FX (CanvasLayer)
└── (debug, solo OS.is_debug_build) LightingDebug / SpeedDebug / StaffDebug CanvasLayers

Nodos AÑADIDOS EN RUNTIME (no están en el .tscn):
  ParallaxBg + SkyDragon            main._ready (fondo de cielo, z=-100)
  Minimap (CanvasLayer)             scripts/minimap.gd — lee Dungeon.cell_seen (niebla)
  VisibilityManager (Node)          scripts/visibility_manager.gd — gatea objetos sticky por celda
  Torches (Node2D)                  DungeonDecor.place_torches → antorchas de pared
  Campfires (Node2D)                DungeonDecor.place_campfires → fogatas (campfire.tscn)
  HUD hijos por código              ShopPanel + InventoryPanel (instanciados en hud._ready)
  spawns                            Enemy*, Boss, Chest*, Merchant, Pickup*, Door*, decor(grupo), Projectile*, Floater*
  _shop screen / AoE / BurnFx flames / boom FX / debug regen button
```

## 0. Autoloads (`project.godot [autoload]`)
```
Rng · GameState · Data · Items · Audio · LightCfg · LightField · FxMaterials · SaveSystem · Fps
  + CombatDirector (NUEVO, ver §6)
  + _mcp_game_helper (addon godot_ai, dev)
```
`boot_splash/image = res://assets/ui/loading.png` (bg 0.05,0.04,0.06; min display 1200 ms). NUEVO.

## 1. Dungeon — PARTIDO en 4 archivos (era god-object ~1875 líneas → dungeon.gd ~815)
`dungeon.gd` se quedó con el **RENDER iso + nav + orquestación**; tres módulos `RefCounted` se llevaron
procgen, decoración y niebla. Los módulos operan sobre el nodo Dungeon vía `d.*` (estado/consts/métodos),
se crean **lazy** (`_ensure_gen`/`_ensure_decor`/`_ensure_fog`) porque hay entradas que NO pasan por
`generate()` (los sandbox llaman `carve_iso_room`/`spawn_wall_torch` directo). La **API pública vieja se
preservó con wrappers** en `dungeon.gd` (p.ej. `is_cell_seen`, `get_door_specs`, `carve_iso_room`,
`spawn_wall_torch`) → enemy/minimap/visibility_manager/sandbox no cambiaron.

```
generate() [ISO]:                                  (dungeon.gd, orquesta)
  _ensure_iso()          capas IsoWalls/Back + tileset + sources de variantes/puertas + material de cara
  _ensure_gen(); _gen.gen_grid()                   grid 64×64 + salas iso + grafo MST+loops   → DungeonGen
  _room_of = _assign_rooms()                        cada celda de piso → su sala (rect/paralelogramo)
  _gen.assign_roles()                               entry/combat/treasure/boss/merchant + spawn/exit  → DungeonGen
  _wall_segments = _build_wall_segments()           fuente lógica de muros (lista WallSegment, ver §2)
  _paint_iso()           piso + _compute_door_faces + _paint_walls (set_cell por borde + variantes + sprites)
  _build_iso_nav()       AStarGrid (⚠ ver abajo)
  _build_iso_boundaries() colisión perímetro (rombos 256×128)
  _ensure_decor(); _decor.place_torches(); _decor.place_campfires()                          → DungeonDecor
  _ensure_fog(); _fog.init_visibility()             cell_seen[] (niebla) listo                → DungeonFog
  regenerated.emit()
```

**Reparto de responsabilidades:**
- `scripts/dungeon_gen.gd` (`class_name DungeonGen`) — PROCGEN: `gen_grid` (grid + paralelogramos iso),
  `_connect_rooms` (MST + ~15% loops → `_room_graph`), `assign_roles` (BFS), `get_door_specs`,
  `carve_iso_room`/`carve_room`/`carve_h`/`carve_v`, `room_center_cell`. Escala salas por profundidad
  (`_room_count_for_depth`: 20 base → hasta 34).
- `scripts/dungeon_decor.gd` (`class_name DungeonDecor`) — ANTORCHAS (`place_torches`, `spawn_wall_torch`,
  anclaje al borde de muro iso + tuning en vivo por panel L) + FOGATAS (`place_campfires`, ~1 de cada 3
  salas, salta la de spawn, `campfire.tscn`).
- `scripts/dungeon_fog.gd` (`class_name DungeonFog`) — NIEBLA de guerra (`init_visibility`,
  `update_visibility`, getters `is_cell_*`/`world_to_cell`) + REVEAL de fachada por sala
  (`update_room_reveal`, `_set_room_faded`, swap tile↔sprite con tween).
- `scripts/dungeon.gd` (`class_name Dungeon`) — RENDER iso (`_paint_iso`/`_paint_walls`/occluders/
  variantes runtime/puertas/material de cara), NAV (`_build_iso_nav`/`next_point`), colisión de borde, y
  la orquestación de `generate()`. También su `_process` empuja luz al shader de muros y delega niebla/reveal a `_fog`.

**Estado compartido que QUEDA en `dungeon.gd`** (los módulos lo leen como `d.*` porque lo producen/consumen
varios sistemas): `grid`, `rooms`, `cell_seen` (fuente de verdad de niebla), `_room_of`, `_room_front`,
`_front_src`, `_wall_segments`, `_gen_room_cells`, `room_roles`, `spawn_cell`/`exit_cell`.

Modo **USE_DOORS=true** (default, banco de la oscuridad): NO talla corredores (mantiene el grafo) + saltea
`_remove_thin_walls` → salas cerradas; `get_door_specs()` + `main._spawn_doors()` crean puertas-teleport
(`door.gd`). `use_test_map` (export) debe quedar en **false** en producción (3 cuartos fijos para debug).

⚠ **Lo que decía "partición futura propuesta" en el doc viejo YA se hizo** (parcial: gen/decor/fog). Falta
si se quiere: separar el pintor de muros (`iso_wall_painter`) del reveal. `dungeon_tiled`/`sky_windows` ya
NO aplican: el path Tiled se borró (ver §1b).

⚠ Bug nav (pendiente): `_build_iso_nav` marca todo no-piso como sólido y luego libera las celdas de piso;
el fix 2026-06-26 dejó de re-marcar sólidas las celdas con muro (se pintan en la celda de PISO interior),
pero el AStarGrid sigue tratando "piso-con-muro" como caminable y el bloqueo real lo pone la colisión de
perímetro, no el nav → revisar si los mobs rozan bordes.

### 1b. Path 2.5D / Tiled — REMOVIDO (2026-06-27)
`generate_from_tiled`, `USE_FIXED_MAPS`, `MAX_FIXED`, `_sky_texture` del loader Tiled y todo el `_paint`
top-down **ya no existen** en `dungeon.gd` ni `main.gd` (`ISO=true` era la única ruta viva). Quedan
referencias SOLO en docs y en `iso_procgen.gd` (script viejo NO usado por `main` — ver §11).

## 2. WallSegment (fuente lógica de muros) — `scripts/wall_segment.gd`
```
WallSegment{ interior_cell, side ∈ {NW,NE,SE,SW}, is_facade(=SE||SW), room_id }
neighbor(cell, side)  ← PARIDAD de fila (TileSet STACKED/offset). NO es un DIR fijo.
INWARD_NORMAL[side]   ← vector hacia el interior de la sala (lo usa DungeonDecor para la luz de antorcha).
_paint_walls (dungeon.gd): por celda detecta lados → esquinas (2 bordes) primero, luego sueltos
  (con VARIACIÓN random por celda) + tile de PUERTA en su cara si corresponde.
  La 1ª pieza va de TILE (set_cell); las extra (celdas raras de 3 bordes) van de Sprite2D overlay.
  front (SE/SW) → IsoWalls (z+1, revelable);  back (NW/NE) → IsoWallsBack (z-1).
```
⚠ Hay **dos criterios de front/back**: `WallSegment.is_facade` (no se lee para rutear) y
`FRONT_SOURCES`/`_wall_layer_for` (el que manda). Las variantes y puertas heredan front/back de su borde
base vía `_variant_base`. WallSegment guarda el lado; el ruteo a capa lo decide `FRONT_SOURCES`.

Variantes de muro y puertas se registran como **sources del TileSet EN RUNTIME** (`_ensure_wall_variants`,
`_ensure_door_sources`), reusando texture_origin + occluder del borde base (Godot 4.6 no persiste el
occluder per-tile en el `.tres` → se setea en runtime).

## 3. Visibilidad / niebla (estilo Diablo: 3 estados) — `scripts/dungeon_fog.gd`
```
FUENTE DE VERDAD = Dungeon.cell_seen[y][x] (sticky, vive en dungeon.gd) + _visible_now (disco
  r=VIS_RADIUS=6, AHORA, vive en DungeonFog)
  update_visibility(pc)  ← lo llama dungeon._process (DESACOPLADO del material de muros).
                           Gate por celda: si el player no cruzó de celda, no rebarre ~169 celdas.
  getters (wrappers en dungeon.gd → DungeonFog): is_cell_seen/is_cell_visible/is_seen_cell/world_to_cell
Consumidores:
  Minimap            → lee cell_seen (memoria/automap)
  VisibilityManager  → gatea cofres/decor/mercader (sticky al verse); rama "vis_threat" quedó muerta
  Enemy              → SE AUTO-GATEA por DISTANCIA (to_player <= mob_reveal_dist) + is_cell_seen
                       ⚠ disco de distancia, NO celda/LOS
  Boss               → NO se gatea (siempre visible) — decisión, choca con "ocultar info"
Reveal de FACHADA (ortogonal a la niebla): update_room_reveal + _set_room_faded (alpha-tween, ROOM_HYST=6
  frames de histéresis). El fog NO apaga caras de muro; el reveal solo baja alpha (REVEAL_ALPHA=0.22) de
  fachadas DELANTERAS. Tile-fachada → se SWAPEA a Sprite2D para tweenear; overlay ya-sprite → solo tween.
```

## 4. Luz (LightCfg → LightField → shader)
```
LightCfg (autoload)  = fuente de verdad de TODOS los knobs (tecla L → user://light_knobs.json)
LightField (autoload):
  _gather()      junta Player/Light + hijos de Torches + dinámicas (add_dynamic)
  pack_lights()  empaqueta para el shader (cada frame) + ambient = amb × foot_ambient
  sample(pos)    tinte por-CPU de entidades foot-lit (player rig)   ← falloff^light_falloff
  entity_material  material unshaded por-píxel compartido (lo usan sprites de mob, orbe, etc.)
wall_face.gdshader  luz por-píxel de caras de muro + entidades (unshaded)  ← mismo modelo
Auras de mob (enemy._glow) = PointLight2D nativo hijo. AHORA con ALTURA (GLOW_HEIGHT=22 ≈ player_height)
  + pisos GLOW_MIN_ENERGY/GLOW_MIN_RADIUS → ILUMINA EL SPRITE del mob, no solo el piso (antes se veían
  negros de lejos). Se registran en LightField vía add_dynamic.
⚠ modelo de luz multiplicado (sample / pack→shader / fragment de muro); cap = LightCfg.LIGHT_CAP × boost.
```
> **Corrección vs doc viejo**: ya NO es cierto que "el aura no autoilumina al mob". Sí lo hace (height + pisos).

## 5. Ordenamiento visual del player
```
Rig = CanvasGroup → Body+Weapon(+Tip)+HandOverlay+StaffArm se compositan ATÓMICO → contra muros van como bloque.
  Bien: la vara no cruza un muro que el cuerpo tapa.  z_index internos ordenan DENTRO del grupo, no contra el mundo.
```
⚠ Comentarios viejos en player.gd describen un z-order per-sprite contra muros que el CanvasGroup ya no
permite (limpiar, no urgente).

## 6. IA de enemigos (mini-FSM por timers) — `scripts/enemy.gd`
```
ai (string): chaser / erratic / shooter   ← arquetipo de movimiento
St (enum):   CHASE → WINDUP → RECOVER       ← FSM de ataque melee (_melee_think)
  CHASE:   orbita su SLOT (ppos + offset por _slot_ang) — no se apilan; pide cupo al director
  WINDUP:  frena + telegraph rojo (~windup s) → pega al final
  RECOVER: frena vulnerable (~recover s) → vuelve a CHASE (histéresis atk_enter<atk_exit)
Director de combate = autoload CombatDirector (scripts/autoload/combat_director.gd):
  try_claim(id)/release(id), MAX_ATTACKERS=3, poda ids muertos. enemy.gd lo llama en
  windup/recover/muerte/sleep/de-aggro. (Antes era static Enemy._atk_active — MOVIDO a autoload.)
Shooter = _shooter_target (kiting) + _shooter_fire (proyectiles). Erratic = wobble en CHASE.
Sleep (perf) = WAKE_RANGE 650px: deja de simular (ortogonal a visibilidad).
Self-light: el sprite usa LightField.entity_material; el aura _glow (con altura) lo autoilumina (ver §4).
take_damage(amount, knockback, is_crit, dmg_color)  ← ahora recibe is_crit + dmg_color (números RPG, §9).
  El número solo aparece si la celda está en tu radio (anti-spoiler).
Golem: al aggro emite Audio.play_at("growl", self) — gruñido POSICIONAL (§8).
Stats por tipo (Data.ENEMIES, opcionales): windup/recover/slot_dist/atk_enter/atk_exit + defaults por arquetipo.
```
> **Corrección vs doc viejo**: el director YA NO es static en Enemy; es el autoload CombatDirector.

## 7. HUD — PARTIDO (era god-object 739 → hud.gd ~273) — `scripts/hud.gd`
```
hud.gd coordina; los paneles pesados viven aparte y se instancian como hijos en _ready:
  _shop = ShopPanel   scripts/ui/shop_panel.gd  — tienda 100% por código (no escena)
  _inv  = InventoryPanel  scripts/ui/inventory_panel.gd — CONSTRUYE DENTRO del nodo HUD/InventoryPanel
                          de la escena (es un controlador liviano; identidad/layout 1:1)
HUD se queda con: barras vida/maná/XP (cache anti-trabajo-por-frame), StatsLabel, BossUI, UpgradePanel,
  pausa, muerte/record, layout responsive 1152×648 → centrado.
TIENDA / MERCADER (API pública preservada): hud.open_shop(m) → _shop.open(m). El HUD escucha
  GameState.shop_requested y llama open_shop (ver §5b).
```

### 7b. Mercader — `scripts/merchant.gd`
Ya **NO busca el HUD por path**. Al apretar E cerca, emite `GameState.shop_requested.emit(self)`; el HUD
escucha esa señal (`GameState.shop_requested.connect(open_shop)`) y abre la tienda. Desacoplado.

## 8. AUDIO (NUEVO) — `scripts/autoload/audio.gd` (autoload `Audio`)
```
Buses (default_bus_layout.tres): World (con reverb) / Music (sin reverb).
  apply_ambient(perfil)  → modula el reverb del bus World por zona ("dungeon" restaura lo tuneado en el
                           panel; "exterior" casi seco). _snapshot_world_reverb guarda el perfil base en _ready.
SFX por nombre (SFX dict) con pool de 8 AudioStreamPlayer (bus World) → Audio.play(key, vol).
SFX POSICIONAL (2D):
  Audio.play_at(key, node)    one-shot posicional (más fuerte al acercarse) — p.ej. growl del golem.
  Audio.loop_at(node, path, vol, dist)  LOOP de fuego con AUTOSTOP por cercanía (antorchas/fogatas):
                                        el emisor lejano se PAUSA (no decodifica → barato con muchos).
  Audio.attach_flame(torch)   wrapper de loop_at con el sfx de antorcha.
  Los emisores de fuego van al grupo "flame_audio"; _process gestiona su pausa por distancia (FLAME_AUDIO_DIST=480).
AMBIENTE de dungeon = 3 capas en LOOP (drone + aire + rumble de tierra, bus Music).
STINGERS lejanos (rugidos/ratas/rumble) random cada ~20-48 s + uno RARO (puerta lejana) cada ~4-5 min,
  en _process (solo en gameplay, hay player). Música = assets/music.mp3 en loop (bus Music).
Pasos = loop dedicado (_footsteps, pitch 1.95), Audio.footsteps(on).
Fallback de carga cruda (FileAccess) si el editor no importó el asset aún.
```

## 9. PROYECTIL + bolt por vara (NUEVO/ampliado) — `scripts/projectile.gd` + `scripts/player.gd`
```
Projectile (Area2D, modelo 2.5D z=altura):
  Orbe del mago = animación `power` del pixi (azul, 4 frames) + explosión `powerboom`. Enemigos = orbe glow generado.
  set_arc(z0, land)  → el bolt del jugador BAJA EN RECTA de z0 (punta) a 0 en el punto clickeado, donde
                       converge con su luz; explota al aterrizar. Enemigos vuelan recto (sin arco).
  set_bolt_frames(travel, impact, scale_mul)  → BOLT PROPIO DE LA VARA: si la vara tiene
       assets/hero/staffs/staffN_bolt/travel|impact/, esos frames REEMPLAZAN el orbe azul (travel ciclado
       en vuelo, impact en la explosión), con estela/luz cálida (fuego). Escala por vara configurable
       (scale_mul = Data.STAFF_BOLT_SCALE[idx], default 1.0; lo gestiona el rigtool → rig_sync → data.gd).
  Anti doble-impacto (_dead): raycast de muro + body_entered no duplican FX/daño.
  Impacto contra MURO: suma un disco azul aditivo POR ENCIMA (las caras son unshaded, la luz no las toca).
Player (player.gd):
  _load_staff_bolt(idx)  → AUTO por carpeta: carga travel/impact de la vara activa y cachea scale_mul.
       Vacío → orbe azul `power`/`powerboom`. Lo llama al equipar/cambiar de vara.
  Al disparar: p.set_arc(...) + (si hay frames) p.set_bolt_frames(...). Daño con crit/fuego → número de color.
```

## 10. FX de combate (NUEVO)
- `scripts/burn_fx.gd` (`class_name BurnFx`, util estático) — `BurnFx.apply(mob)`: 3-5 llamitas random,
  animadas (ADD+unshaded), arden ~1 s y se desvanecen, HIJAS del mob (lo siguen). Aplicado EXTERNO (no toca
  enemy.gd): lo invocan `projectile.gd` (bolt de fuego) y `aoe.gd`. Anti-saturación por meta `_burn_until`.
- `scripts/floater.gd` (`scenes/floater.tscn`) — número de daño estilo RPG: pop de escala, scatter
  horizontal, outline, ease-out + fade. CRÍTICO = dorado (`CRIT_GOLD`) y más grande; color propio por tipo
  (naranja = fuego). Lo crea `GameState.floater(pos, text, color, is_crit)`.
- `scripts/aoe.gd` (`class_name AoE`) — ataque de ÁREA. En player: tecla **E (interact) cuando no hay nada
  para interactuar cerca** (`_try_aoe`, cuesta maná + cooldown). Planta un glifo en el piso, ~1 s de buildup,
  EXPLOTA: daño en óvalo + glow + shake + sfx, prende a los mobs (`BurnFx.apply`). Tamaño/achatado/posición
  de las llamas salen de `assets/fx/aoe_config.json` (editable con la AoE Glyph Tool, ver memoria de tools).
  ⚠ existe un input `nova` (R / click derecho) en project.godot pero NO está cableado en player.gd.
- `scripts/campfire.gd` (`class_name Campfire`, `scenes/campfire.tscn`) — fogata: sprite animado (unshaded)
  + luz cálida con parpadeo + crepitar posicional. `DungeonDecor.place_campfires` la coloca ~1/3 de salas.

## 10.bis. Barra de habilidades (NUEVO 2026-06-28) — `scripts/ui/skill_bar.gd` + `scripts/ability_defs.gd` + `player.gd`
```
AbilityDefs (RefCounted, class_name) — registro data-driven: LIST{id→{name,desc,cooldown,mana,color}},
  DEFAULT_SLOTS, ids(), icon(id) (PNG del autor en assets/ui/skills/<id>.png o gema generada).
player.gd — skill_slots[4] (ids) + skill_cd[4] (cooldown restante, decrementa en _tick_timers).
  Input skill_1..4 (teclas 1-4) → _cast_slot(i): chequea cooldown+maná, llama _cast_ability(id) (efecto),
  setea skill_cd[i]=cooldown y resta maná. _cast_ability(id) (match): meteor (=AOE), nova (orbes radiales),
  heal (maná→vida), blink (dash al cursor, reusa move_and_slide → no cruza muros), frost (PBAoE daño+empuje
  + anillo visual), dash (delega a _try_dash). assign_skill(slot,id) → GameState.skills_changed.
  Persistido en to_save/load_save ("skill_slots").
SkillBar (Control, hijo del HUD) — barra de 4 slots abajo-centro (arriba de la XP): bg slot.png + ícono +
  overlay de cooldown que se DRENA (offset_top) + segundos + tecla. Atenúa el ícono sin maná. Panel de
  asignación (tecla skills_menu=K): pausa, elegís slot + habilidad → player.assign_skill. Lee GameState.player.
CAMBIO: el AoE ya NO se castea con E (interact); migró al slot 1 (meteor). E quedó solo para interactuar.
```

## 4.bis. Cull de luces por proximidad (NUEVO 2026-06-28) — `light_field.pack_lights`
El pack para el shader topa en `MAX_LIGHTS=64` con estáticas primero y auras de mob (`_dynamic`) al final →
en pisos con muchas antorchas/fogatas las auras quedaban fuera y el mob salía negro. Fix: `LIGHT_CULL_DIST=560`
descarta luces a más de esa distancia (+ su radio) del jugador — no iluminan ningún píxel en pantalla (cámara
clavada, zoom 4) pero robaban slots. La luz del jugador (dist 0) nunca se descarta. NO cambia el modelo de luz;
`sample()` (CPU, sin cap de slots) queda igual. La luz NATIVA del piso (PointLight2D) no se ve afectada.

## 3.bis. Minimapa = radar centrado en el jugador (CAMBIO 2026-06-28) — `minimap.gd`
El minimapa chico ahora es un **radar de tamaño FIJO** (`MINI_VIEW=150`) con el jugador clavado al centro como
punto; el mapa se desliza. Implementado con un `AtlasTexture` (`_mini_atlas`) sobre `_tex` cuya `region` sigue
la celda del jugador (`MINI_TILES=28` de ancho). El shader circular enmascara por UV del box (sin cambios). El
mapa grande (tecla M) sigue siendo vista general con marcadores absolutos.

## 11. PENDIENTES / deuda que SIGUE (verificado contra el código)
- **nav AStarGrid**: el "piso-con-muro" queda caminable; el borde real lo bloquea la colisión de perímetro,
  no el nav (ver ⚠ en §1).
- **DungeonDecor.place_torches** sigue asumiendo salas CARTESIANAS (`r.position`/`r.size` + filas/columnas)
  → mal colocadas en salas iso (paralelogramos). `place_campfires` sí usa celda de piso real.
- **Boss nunca se oculta** (no entra al gating de visibilidad) — choca con "ocultar info" (§3). Tiene **aura propia** (`boss._glow`, PointLight2D rojizo con altura, como los mobs pero más fuerte: energy 2.4 / scale 1.3 / height 30) → se autoilumina en la oscuridad (antes se veía negro de lejos: no tenía luz propia).
- **Gating de mobs por DISTANCIA, no LOS** (disco `mob_reveal_dist`, §3/§6).
- **Sandbox sin tocar**: `closed_room_test` / `iso_test` / `light_test` (scenes + scripts) — bancos de prueba
  aislados; `iso_procgen.gd` + `iso_mob_spawner.gd` NO los usa `main` (legacy del merge).
- **Tilesets `iso_dungeon_v*` chatarra** — el vivo es `assets/iso/iso_pixel.tres`.
