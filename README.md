# Cárcel del Cuteo — port Godot

Roguelike de mazmorras **isométrico** en **Godot 4.6**. Port a Godot del juego original en Pixi.
Pisos procedurales con salas iso cerradas + puertas-teleport, iluminación por-píxel (caras de muro
foot-lit + auras), niebla de guerra estilo Diablo, combate ARPG y descenso por zonas hasta el jefe.

Rama de trabajo: **`iso-merge`**. Escena de producción: **`scenes/main.tscn`**.

> 👉 **Si sos un agente/dev arrancando, leé [`AGENTS.md`](AGENTS.md) primero**, y después
> [`docs/project_memory.md`](docs/project_memory.md) (estado/decisiones) y
> [`docs/architecture_notes.md`](docs/architecture_notes.md) (cómo funciona cada sistema).

## Estructura

- **`scripts/`** — lógica del juego.
  - `main.gd` — flujo de pisos (genera, ubica spawns/jefe/cofres/mercader, save/load, salida).
  - `dungeon.gd` — nodo del piso: render iso (muros/piso/occluders/puertas) + nav + API + orquestación. Partido en módulos:
    - `dungeon_gen.gd` (procgen), `dungeon_decor.gd` (antorchas+fogatas), `dungeon_fog.gd` (niebla+reveal).
  - `player.gd`, `enemy.gd`, `boss.gd`, `projectile.gd`, `hud.gd`, y props (`door`, `merchant`, `chest`, `campfire`, `torch`…).
  - `scripts/ui/` — `shop_panel.gd`, `inventory_panel.gd` (los coordina `hud.gd`).
  - `scripts/autoload/` — singletons (`game_state`, `data`, `items`, `audio`, `light_cfg`, `light_field`, `fx_materials`, `save_system`, `combat_director`, `rng`…).
- **`scenes/`** — escenas `.tscn` (`main` = producción; + sandboxes `closed_room_test`/`iso_test`/`light_test`).
- **`shaders/`** — `wall_face.gdshader` (luz por-píxel de caras de muro + entidades).
- **`assets/`** — tiles iso, fx, sfx, hero/staffs, mobs, ui (incl. `ui/loading.png` = boot splash), `story/`.
- **`tools/`** — tooling web propio (rig de varas/anims/bolts, AoE glyph). Server único: `py tools/serve.py` (8765).
- **`docs/`** — arquitectura, memoria de proyecto, planes (narrativa, fx, visibilidad) y lore.

## Correr

Abrí el proyecto en Godot 4.6 y dale Play (corre `scenes/main.tscn`). El juego entra directo al gameplay
(no hay menú al inicio); el boot splash muestra `assets/ui/loading.png` mientras carga.

## Tooling (rig de varas / bolts / AoE)

```
py tools/serve.py        # server único en http://localhost:8765 (auto-guarda)
```
Abrí `http://localhost:8765/tools/index.html` — tabs: Rig/Varas, Wall Origin, AoE Glyph.
`py tools/rig_sync.py` sincroniza el rig editado → `scripts/autoload/data.gd` (`STAFF_RIG`, `STAFF_ANIM_FPS`, `STAFF_BOLT_SCALE`).
