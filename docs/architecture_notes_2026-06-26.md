# Notas de arquitectura — 2026-06-26

Mapa de los sistemas reales del juego (path vivo: iso, `ISO=true`). Para deuda/cleanup ver
`code_audit_2026-06-26.md` y `cleanup_candidates_2026-06-26.md`.

## Árbol de escena (producción)
```
Main (Node2D, y_sort)              scripts/main.gd  — flujo: _build_floor, spawns, save/load, exit
├── Dungeon (TileMapLayer)         scripts/dungeon.gd — piso + GENERA todo (ver abajo)
│   ├── IsoWalls (TileMapLayer z=+1)      fachada delantera SE/SW (tapa al player) + reveal
│   ├── IsoWallsBack (TileMapLayer z=-1)  muros traseros NW/NE (el player los tapa)
│   └── RoomDarkness  ← YA NO EXISTE (overlay borrado esta sesión)
├── Player (CharacterBody2D)       scripts/player.gd
│   ├── Rig (CanvasGroup)          ← composita body+weapon+overlay+staffArm ATÓMICO contra muros
│   ├── Camera2D (zoom, sigue al player → player centrado, mapa se desliza)
│   └── Light (PointLight2D)       ← charco del player (textura horneada o procedural por player_soft)
├── HUD (CanvasLayer)              scripts/hud.gd — vida/maná/XP/jefe/inventario/tienda/pausa/muerte
├── (spawns en Main): Enemy*, Boss, Chest*, Merchant, Pickup*, Door*, decor (grupo), Projectile*
├── Minimap (CanvasLayer)         scripts/minimap.gd — lee Dungeon.cell_seen (niebla)
├── VisibilityManager             scripts/visibility_manager.gd — gatea objetos sticky por celda
├── Ambient (CanvasModulate)      ← lo pisa LightCfg.ambient_color() vía lighting_debug
└── Torches (contenedor)          ← LightField junta estas luces + Player/Light
```

## 1. Dungeon / procgen (god-object, 1875 líneas — candidato a partir)
```
generate() [ISO]:
  _gen_grid()            grid 64×64 + salas iso (paralelogramos) + _connect_rooms (MST+loops) + roles
  _assign_rooms()        cell → room_id
  _assign_roles()        entry/combat/treasure/boss/merchant + setea spawn_cell/exit_cell
  _build_wall_segments() → _wall_segments (lista WallSegment) = FUENTE LÓGICA de muros
  _paint_iso()           piso + _paint_walls (set_cell por borde) + variantes random
  _build_iso_nav()       AStarGrid (⚠ bug: marca piso-con-muro sólido)
  _build_iso_boundaries() colisión perímetro (rombos)
  _place_torches()       (⚠ asume salas cartesianas)
  _init_visibility()     cell_seen[] (niebla)
  regenerated.emit()
```
Modo **USE_DOORS=true**: no talla corredores (mantiene el grafo) + saltea `_remove_thin_walls` → salas
cerradas; `get_door_specs()` + `main._spawn_doors()` crean puertas-teleport (`door.gd`).
**Partición futura propuesta**: `dungeon_gen` (grid/grafo), `iso_wall_painter` (muros), `dungeon_reveal`
(fachadas), `fog_of_war` (cell_seen), `dungeon_tiled` (import Tiled), `sky_windows` (cielo). Borrar el path 2.5D.

## 2. WallSegment (fuente lógica de muros)
```
WallSegment{ interior_cell, side ∈ {NW,NE,SE,SW}, is_facade(=SE||SW) }
neighbor(cell, side)  ← PARIDAD de fila (TileSet STACKED/offset). NO es un DIR fijo.
_paint_walls: por celda detecta lados → esquinas (2 bordes) primero, luego sueltos.
  front (SE/SW) → IsoWalls (z+1, revelable);  back (NW/NE) → IsoWallsBack (z-1).
```
⚠ Hay **dos criterios de front/back**: `WallSegment.is_facade` (no se lee) y `FRONT_SOURCES`/`_wall_layer_for`
(el que manda). WallSegment guarda el lado pero el ruteo a capa lo decide `FRONT_SOURCES`.

## 3. Visibilidad / niebla (estilo Diablo: 3 estados)
```
FUENTE DE VERDAD = Dungeon.cell_seen[y][x] (sticky) + _visible_now (disco r=VIS_RADIUS=6, AHORA)
  _update_visibility(pc)  ← corre en _update_iso_wall_mat (⚠ acoplado al material de muros)
  getters: is_cell_seen/is_cell_visible/is_seen_cell/world_to_cell
Consumidores:
  Minimap   → lee cell_seen (memoria/automap)
  VisibilityManager → gatea cofres/decor/mercader (sticky al verse)
  Enemy     → SE AUTO-GATEA por DISTANCIA (to_player <= mob_reveal_dist) + is_cell_seen
              ⚠ esto es disco de distancia, NO celda/LOS; la rama vis_threat del manager quedó muerta
  Boss      → NO se gatea (siempre visible) — decisión, choca con "ocultar info"
Reveal de FACHADA (ortogonal a la niebla): _update_room_reveal + _set_room_faded (alpha-tween).
  Regla dura: el fog NO apaga caras de muro; el reveal solo baja alpha de fachadas delanteras.
```

## 4. Luz (LightCfg → LightField → shader)
```
LightCfg (autoload)  = fuente de verdad de TODOS los knobs (tecla L → user://light_knobs.json)
LightField (autoload):
  _gather()      junta Player/Light + hijos de Torches  (⚠ NO junta auras de mob)
  pack_lights()  empaqueta para el shader (cada frame) + ambient = amb × foot_ambient
  sample(pos)    tinte por-CPU de entidades foot-lit (player rig, mobs)   ← falloff^light_falloff
wall_face.gdshader  luz por-píxel de caras de muro + entidades (unshaded)  ← mismo modelo, 3ª copia
Auras de mob (enemy._glow) = PointLight2D nativo hijo, ilumina el PISO (no entra al pool de LightField).
⚠ modelo de luz TRIPLICADO (sample / pack→shader / fragment); cap=1.4 en 4 lugares.
```

## 5. Ordenamiento visual del player
```
Rig = CanvasGroup → body+weapon+hand_overlay+staffArm se compositan ATÓMICO → contra muros van como bloque.
  Bien: la vara no cruza un muro que el cuerpo tapa.  z_index internos (weapon=1, overlay=2, body via anim)
  ordenan DENTRO del grupo, no contra el mundo.
⚠ comentarios en player.gd:~350-363 describen un z-order per-sprite contra muros que el CanvasGroup ya no
  permite (la "punta de la vara delante del muro" no aplica). Limpiar comentarios (no urgente).
```

## 6. IA de enemigos (mini-FSM por timers)
```
ai (string): chaser / erratic / shooter   ← arquetipo de movimiento
St (enum):   CHASE → WINDUP → RECOVER       ← FSM de ataque melee (_melee_think)
  CHASE:   orbita su SLOT (ppos + offset por _slot_ang) — no se apilan; pide cupo al director
  WINDUP:  frena + telegraph rojo (~windup s) → pega al final
  RECOVER: frena vulnerable (~recover s) → vuelve a CHASE (histéresis atk_enter<atk_exit)
Director de combate = static Enemy._atk_active + MAX_ATTACKERS=3 (tope simultáneo; poda ids muertos)
  release en muerte/sleep/de-aggro (3 caminos, verificado sin leak).
Shooter = _shooter_target (kiting) + _shooter_fire (proyectiles). Erratic = wobble en CHASE.
Sleep (perf) = WAKE_RANGE 650px: deja de simular (ortogonal a visibilidad).
Stats por tipo (Data.ENEMIES, opcionales): windup/recover/slot_dist/atk_enter/atk_exit + defaults por arquetipo.
⚠ Director conviene moverlo a autoload propio (hoy vive como static en Enemy).
```
