# Memoria del proyecto — actualizado 2026-06-27 (para agentes/devs futuros)

> Leé esto PRIMERO antes de tocar nada. Evita repetir diagnósticos viejos y revertir fixes.
> Complementos: `architecture_notes.md` (cómo funciona cada sistema),
> `visibility_darkness_plan.md` (oscuridad/fog, ojo: tiene partes viejas), `spell_fx_plan.md`,
> `PLAN_NARRATIVO.md` / `lore/PROPUESTAS_LORE_2026-06-26.md` (intro narrativa, pendiente).
> ⚠ `code_audit_2026-06-26.md` y `cleanup_candidates_2026-06-26.md` son **snapshots del 2026-06-26**:
> su deuda dominante (god-objects `dungeon.gd`/`hud.gd`, path 2.5D/Tiled muerto, director static en Enemy)
> **YA SE RESOLVIÓ** (ver §3.bis y §4). Leelos como histórico, no como TODO vigente.

## 1. Estado actual confirmado
- **Godot 4.6**, juego isométrico 2D tipo Diablo-like / dungeon-crawler. Rama `iso-merge` (los refactors de §3.bis y las features de §3.ter están **commiteados y pusheados**).
- Arranque = **`scenes/menu.tscn`** (menú de inicio; lanza `main.tscn` al jugar). El menú existe desde el 2026-06-15 pero el giro a iso (commit `9abb2ad`, 06-23) puso `iso_test` como arranque y lo dejó afuera; **reactivado el 2026-06-27**. Escena de juego = **`scenes/main.tscn`**; `Dungeon.use_test_map` debe quedar en **false** en producción (default ya es false).
- Procgen **iso ACTIVO** (`dungeon.gd`, `const ISO := true`). Modo **USE_DOORS=true**: salas cerradas + puertas-teleport (banco de pruebas de la oscuridad).
- Muros = **`WallSegment`** (fuente lógica). **NW/NE = traseros**, **SE/SW = delanteros/fachada**. Capas `IsoWalls` (z+1) / `IsoWallsBack` (z-1). `neighbor()` depende de **paridad de fila** (TileSet STACKED).
- TileSet vivo = **`assets/iso/iso_pixel.tres`** (los `iso_dungeon_v*` son chatarra).
- Iluminación/antorchas/occluders **sensibles**: no tocar sin test visual. Knobs en `LightCfg` (tecla L, persiste en `user://light_knobs.json`). Paneles debug (L=luz, V=velocidad) gateados tras `OS.is_debug_build()` → ocultos en release.
- Visibilidad/fog: oscuridad por luz real + grilla `cell_seen`/`_visible_now` en Dungeon (fuente de verdad), minimapa y `visibility_manager` la consumen. NO hay overlay fullscreen oscurecedor.
- **Audio inmersivo activo** (`audio.gd`): buses World (reverb) / Music, ambiente por zona, SFX posicional. Ver §3.ter.
- **Boot splash** (pantalla de carga): `project.godot → boot_splash/image = assets/ui/loading.png`.

## 2. Decisiones de diseño tomadas (no reabrir sin motivo)
- **Muros bajos: descartado.** Muro que tapa al player → **transparencia/reveal de fachada**, NO borrar muros.
- **Oscuridad = ausencia de luz** (no un velo/overlay). **Explorado = recordado** (minimapa lee `cell_seen`), no iluminado para siempre. Estilo Diablo 2.
- 3 estados de visibilidad: **visible ahora / explorado-recordado / no visto.** Las caras de muro visibles desde el cuarto activo **NO** se oscurecen por limitar con un cuarto no visitado.
- Player rig = **CanvasGroup** (atómico contra muros) — decisión buena.
- IA de mobs: por ahora caminata + ataque con **windup/recovery + slots + director (máx 3) + histéresis**. No planear IA compleja sin afinar esto primero.
- Cámara: **player fijo al centro, el mapa se desliza** (Camera2D hija, `make_current`).
- **Luz de mobs CON altura**: el aura del mob (`_glow`, `GLOW_HEIGHT≈22`) ilumina el **sprite del mob**, no solo el piso (antes se veían negros de lejos). Pisos mínimos (`GLOW_MIN_ENERGY/RADIUS`) garantizan que se vean aunque los knobs de piso estén bajos. No revertir a aura sin altura.

## 3. Fixes importantes que NO deben revertirse
- `main.tscn` / `dungeon.gd`: `use_test_map = false` (el bug "regen da mismo mapa" era el test map activo, **no** el seed/RNG).
- `WallSegment.neighbor()` por **paridad de fila** (no DIR fijo) — resolvió el serrucho de muros.
- Migración de oscuridad: overlay `room_darkness.gd` **borrado** a propósito (era BG3, no D2). No re-agregar un velo por-sala.
- Minimapa **lee** `dungeon.cell_seen` (Dungeon es la fuente de verdad, no la UI).
- Antorchas: anclaje por **borde/cara de muro** iso (`DungeonDecor.spawn_wall_torch`), no por celda top-down vieja. (El `place_torches` del procgen real todavía asume salas cartesianas — bug pendiente, NO es un fix a revertir; ver §5.)
- Variantes de muro: se registran como **sources del TileSet en runtime** (`_ensure_wall_variants`), reusan origins base. No hardcodear en el `.tres`.
- **Bug de nav (FIX aplicado, no revertir):** `dungeon.gd _build_iso_nav` ya NO solidifica las celdas de piso que tienen muro — los mobs pueden rutear hasta bordes/esquinas. La colisión real de muros la da `_build_iso_boundaries`, aparte del nav. (Validación runtime fina sigue en manos de Felipe.)
- Auras de mob: el `_glow` tiene **altura** (no revertir, ver §2).

## 3.bis. Refactors YA HECHOS (esto es la estructura ACTUAL, no deuda)
> Todo lo de abajo está commiteado/pusheado en `iso-merge`. Lo que antes este doc listaba como "god-objects a partir" y "path 2.5D muerto" **ya está resuelto**.
- **`dungeon.gd` se partió** (era ~1875 líneas) en 3 módulos `RefCounted` + el nodo orquestador:
  - `scripts/dungeon_gen.gd` → `class_name DungeonGen` (RefCounted): **procgen** (grid 64×64, salas iso, grafo MST+loops, roles, `carve_iso_room`).
  - `scripts/dungeon_decor.gd` → `class_name DungeonDecor` (RefCounted): **antorchas + fogatas** (`spawn_wall_torch`, `place_torches`, `place_campfires`).
  - `scripts/dungeon_fog.gd` → `class_name DungeonFog` (RefCounted): **niebla + reveal** (`init_visibility`, `update_visibility`, `update_room_reveal`, `_set_room_faded`).
  - `scripts/dungeon.gd` (~813 líneas, `class_name Dungeon extends TileMapLayer`): **render iso + nav + API pública + orquestación**. Crea los 3 helpers y los coordina.
  - **Estado compartido que SIGUE viviendo en `dungeon.gd`** (los helpers lo leen/escriben): `grid`, `rooms`, `cell_seen`, `_room_of`, `_room_front`, `_front_src`.
- **Path 2.5D/Tiled muerto: REMOVIDO** de `dungeon.gd` y `main.gd` (ya no existen `generate_from_tiled` / `USE_FIXED_MAPS` / `_paint` 2.5D). Comentario de cierre en `dungeon.gd` con fecha 2026-06-27. (Los `.tmx`/`.tsx` en `maps/` pueden seguir como assets sueltos pero ya no se cargan.)
- **`hud.gd` se partió** (era 739 líneas → ~272): ahora **coordina** dos paneles que viven aparte:
  - `scripts/ui/shop_panel.gd` → `class_name ShopPanel` (UI + compra/venta/heal de la tienda).
  - `scripts/ui/inventory_panel.gd` → `class_name InventoryPanel` (inventario HD: equip + bag).
- **Director de combate → autoload**: era `static Enemy._atk_active`; ahora es `scripts/autoload/combat_director.gd` (autoload **CombatDirector**, `try_claim()`/`release()`, MAX 3). `enemy.gd` lo usa, ya no hay static.
- **Mercader desacoplado del HUD**: `merchant.gd` emite `GameState.shop_requested(self)`; el HUD escucha (`GameState.shop_requested.connect(open_shop)`). Ya no hace `get_node("HUD")`. Señal declarada en `game_state.gd`.

## 3.ter. Features nuevas (2026-06-27, commiteadas/pusheadas)
- **Audio inmersivo** (`scripts/autoload/audio.gd`): buses **World** (reverb) / **Music**; `apply_ambient()` aplica reverb/perfil por zona; SFX **posicional** con autostop (`Audio.loop_at` para loops de fuego, `Audio.play_at` para one-shots 2D); **3 capas de ambiente** (drone / aire / rumble); **stingers lejanos** (rugidos/ratas/rumble cada ~20-48 s).
- **Bolt de fuego por vara** (`projectile.gd` + `player.gd`): frames `assets/hero/staffs/staffN_bolt/{travel,impact}/` cargados **auto por carpeta** + **escala por vara** vía `Data.STAFF_BOLT_SCALE` (dict, lo llena el rigtool; vacío = escala 1.0).
- **FX de combate:**
  - `scripts/burn_fx.gd`: llamitas chiquitas random sobre mobs **quemados** (daño de fuego).
  - `scripts/floater.gd`: números de daño RPG con **crit** (dorado + overshoot) y **fuego** (naranja).
  - `scripts/aoe.gd`: **ataque de área**. ⚠ Se dispara con la tecla **E** (acción `interact`, keycode 69), NO con `nova`/R. La acción `nova` (R, keycode 82) existe en `project.godot` pero **está sin usar**.
  - `scripts/campfire.gd`: **fogatas** de leña (sprite animado + luz cálida con flicker + crackle posicional). Las coloca `DungeonDecor.place_campfires`.
- **Boot splash**: `assets/ui/loading.png` (ver §1).
- **Tools de autor** en `tools/`: server único `py tools/serve.py` (puerto 8765, auto-guarda) sirve Godot + arte; `rigtool.html` (varas/anims/bolts), `aoe_glyph_tool.html` (coloca las llamas del AoE), `wall_origin_tool.html`, `index.html` con tabs; `rig_sync.py` (converter → `data.gd`). El pixi/rigserver viejo está deprecado.

## 4. Trabajo en transición (esperá inconsistencias acá)
- **Visibilidad de mobs sin unificar**: el gating de **mobs es por distancia (disco `mob_reveal_dist`)** + `is_cell_seen`, NO por celda/LOS; la rama `vis_threat` del `visibility_manager` quedó muerta; el **boss nunca se oculta** (siempre visible). Unificar a futuro (idealmente shadowcasting). `visibility_darkness_plan.md` describe parte del comportamiento viejo.
- **Modelo de luz triplicado** (`LightField.sample` / push de uniforms / `wall_face.gdshader`) + `cap=1.4` mágico en varios lados: cambiar uno exige sincronizar los otros. Frágil, no urgente.
- Escenas/scripts **sandbox** sin mover (`iso_test`, `closed_room_test`, `light_test` + sus scripts `iso_procgen.gd`/`iso_mob_spawner.gd`/`iso_wall_occluder.gd`). OJO: `dungeon.gd`/`torch.gd`/`wall_segment.gd` aparecen en esas escenas **pero son producción**.
- Posible limpieza de tilesets `iso_dungeon_v*` y assets iso viejos (chatarra de iteración, ~21 `.tres`).

## 5. Pendientes / bugs conocidos (NO son fixes a revertir)
- **Nav marca piso-con-muro:** ya se removió la solidificación errónea (ver §3), pero queda **validación runtime fina** de Felipe (mobs llegan a bordes/esquinas y NO atraviesan muros).
- **`DungeonDecor.place_torches` asume salas cartesianas** (rect bbox) → en salas iso (paralelogramos) algunas antorchas quedan mal ubicadas. El `spawn_wall_torch` por-borde es el correcto; el placement masivo aún no usa esa lógica.
- **Boss**: ahora tiene **aura propia** (`_glow`, PointLight2D rojizo, energy 2.4 / height 30) → se autoilumina en la oscuridad; antes se veía **negro de lejos** por no tener luz propia (los mobs sí la tienen). Ojo: "siempre visible" (§4) era sobre el FOG, no sobre la luz — sin aura igual quedaba negro. Sigue sin ocultarse por fog (ver §4); tope de summon cuenta TODOS los Enemy del piso (puede invocar 0) y el daño de contacto va sin `hit_cd` (balance, requiere decisión de Felipe).
- **Sandbox sin mover** + **tilesets `iso_dungeon_v*` chatarra** (ver §4).
- **ESC → menú** pendiente.
- **Sistema de intro narrativa pendiente** (asset `assets/story/intro_council.png` ya guardado; ver `PLAN_NARRATIVO.md`).
- (Robustez histórica del audit, si se retoma): save atómico (`.tmp`+rename) y distinguir save corrupto vs ausente; `hash([run_seed, depth])` no estable entre versiones de engine.

## 7.bis. Sesión autónoma 2026-06-28 (cambios aplicados, SIN commitear)
Tanda de notas de Felipe resueltas de una. Todo compila headless (exit 0, sin SCRIPT ERROR). Falta que pruebe jugando.
- **CRASH ESC arreglado** (`audio.gd:_process`): casteaba `GameState.player` ya liberado al volver al menú. Ahora `is_instance_valid` antes del `as Node2D`. Era el "Trying to cast a freed object" que cerraba el juego.
- **Luz de mobs inconsistente → FIX** (`light_field.gd pack_lights`): root cause = `MAX_LIGHTS=64`, estáticas (hasta 32 antorchas+fogatas de TODO el piso) primero y auras de mobs (`_dynamic`) al final → en pisos cargados las auras quedaban fuera del pack y el mob salía negro. Fix: cull por proximidad al jugador (`LIGHT_CULL_DIST=560`): una luz lejana no ilumina ningún píxel en pantalla (cámara clavada, zoom 4) pero robaba slot. Libera slots para las auras cercanas. NO toca el modelo de luz.
- **Difusión luz del jugador** (`player.gd _apply_light_tex` + `light_cfg.gd`): el charco tenía borde duro aun con `player_soft=4.0` (su máx). Cambié la curva `pow(1-d,p)` por **gaussiana con borde restado** (perímetro difuso, sin anillo) y subí el tope del slider a 8. El JSON de Felipe ya tenía `player_soft=4.0` → ya usa la nueva curva.
- **Minimapa centrado en el jugador** (`minimap.gd`): el radar ahora es de tamaño FIJO y el jugador queda clavado al centro como un punto; el mapa se desliza (via `AtlasTexture` cuya región sigue la celda del jugador). El mapa grande (M) sigue siendo vista general. `MINI_VIEW=150`, `MINI_TILES=28`.
- **Barra de habilidades RPG** (NUEVO): `scripts/ability_defs.gd` (AbilityDefs, registro data-driven) + `scripts/ui/skill_bar.gd` (SkillBar, barra de 4 slots con cooldown que se drena + coste de maná + panel de asignación tecla **K**) + lógica en `player.gd` (`skill_slots`/`skill_cd`, `_cast_slot`/`_cast_ability`, persistido en save). Input nuevo `skill_1..4` (teclas 1-4) + `skills_menu` (K) en project.godot. Señal `GameState.skills_changed`. 6 habilidades: **Meteoro** (= el viejo AoE), **Nova Arcana** (orbes radiales), **Parpadeo** (dash al cursor), **Toque Sanador** (maná→vida), **Estallido Glacial** (PBAoE daño+empuje), **Impulso** (dash). Default slots: meteor/nova/blink/heal. **CAMBIO**: el AoE ya NO se castea con E (migró al slot 1); E quedó solo para interactuar (cofres/mercader ya escuchaban E ellos mismos). Íconos = gema placeholder generada (Felipe pone `assets/ui/skills/<id>.png`). _Dead code menor: `player._try_aoe`/`_interactable_near` quedaron huérfanos._
- **Impacto de fuego con dirección** (`projectile.gd _impact`): el boom propio de la vara ahora rota a `velocity.angle()` (alineado al bolt, como pidió). El powerboom radial default NO rota.
- **Barra de XP más abajo** (`main.tscn` XPBar): trasladada 16px hacia abajo (mantiene altura). Ajuste fino, Felipe puede retocar.
- **Botón debug "Regenerar mapa" REMOVIDO** (`main.gd`): borrado `_add_debug_regen_button`/`_debug_regen` y su llamada.
- **Pantalla gris post-intro**: causa = clear color por defecto de Godot (gris) durante `change_scene_to_file` (síncrono) + `generate()` pesado en `_ready`. Apliqué `rendering/environment/defaults/default_clear_color=Color(0.05,0.04,0.06)` en project.godot → el hueco ya no es gris sino oscuro/coherente. PENDIENTE (para mañana, junto al intro que está en revisión narrativa): precargar `main.tscn` con `load_threaded` DURANTE la intro (`narration_player.gd start/_finish`) + overlay `loading.png` en `main._ready` con un `await process_frame`. Ver `docs/webgl_to_desktop_upgrades.md` no; ver notas de la sesión.
- **WebGL→desktop**: el renderer YA está bien (Forward+, glow 2D, HDR 2D activos). Informe en `docs/webgl_to_desktop_upgrades.md`. Quick wins pendientes (decisión de Felipe, son visuales/arte): MSAA 2D (off), `Engine.max_fps`, estela del bolt CPU→GPU, `post_fx.gdshader` muerto. Apliqué solo el clear color (no-visual, además fix del gris).

### Ronda 2 (mismo día, tras feedback de Felipe jugando)
- **CRASH pack_lights / ESC** (`light_field.gd:64`): el cull que agregué casteaba `GameState.player as Node2D` sin `is_instance_valid` → crasheaba al volver al menú (y era el "ESC a veces cierra"). Guardado. (Mismo patrón que el de audio.)
- **Franjas negras a los costados**: faltaba `window/stretch/aspect="expand"` en project.godot (default "keep" letterboxeaba). Agregado → ocupa todo el ancho.
- **Barra de habilidades no se veía (slots/íconos)**: en run nueva la señal `skills_changed` no llegaba (player no listo al crear la barra). Fix: `skill_bar.gd` sincroniza íconos en `_process` (via `_shown`) + backdrop oscuro por slot (visible aunque slot.png sea sutil) + guard `is_instance_valid` en `_process`.
- **Panel de habilidades (K) se iba de pantalla**: envuelto en `CenterContainer` (se autocentra + dimensiona al contenido) + botones más chicos. Ya no depende de la resolución.
- **Banding/anillos en el charco del jugador**: el `light_pool` por código era RGBA8 (256 niveles) y se samplea NEAREST escalado → los escalones del degradé se veían como aros. Pasado a **RGBAH (half float)** + s=320 (`player.gd _apply_light_tex`) → degradé continuo.
- **Minimapa doble aro dorado**: `bg` y el mapa compartían el material del shader (ambos dibujaban el aro). Shader `minimap_circle.gdshader` ahora tiene uniform `draw_ring`; el mapa usa `draw_ring=0` (solo recorta) → un solo aro.
- **Pantalla "vacía" post-intro/carga**: agregado **overlay de carga** (`loading.png`) en `main._ready` con `await get_tree().process_frame` antes del procgen pesado → se ve el loader mientras genera, en vez del hueco. (`_show_loading_overlay`/`_hide_loading_overlay`.)
- **Barra de XP**: bajada más (offset_top=-133, offset_bottom=40).
- **PENDIENTE минimapa iso**: el minimapa dibuja la grilla cuadrada; el mundo es iso (salas = paralelogramos en grid-space via `carve_iso_room`) → la forma no condice. Opciones investigadas (no implementado, necesita ojo de Felipe): (1) dejar ortogonal/cuadrado (legible, estándar en muchos iso); (2) proyectar el minimapa a iso (rombo) con la misma transform `map_to_local` 2:1 — shader que samplea el atlas con la inversa iso, o replotear las celdas vistas en posiciones iso; (3) skew via wrapper Node2D (rompe la máscara circular, descartado). Recomendación: implementarlo en vivo la próxima para iterar visual.

### Dudas abiertas para Felipe (preguntar mañana)
1. **Fuentes UI**: verifiqué en headless que TODAS cargan bien (Cinzel/Garamond + LabelSettings, sin errores) y toda la UI pasa por UiTheme. NO hay bug de código. Casi seguro es **caché del editor abierto en vivo** (agregaste las fuentes hoy con Godot abierto) → cerrar y reabrir Godot (o borrar `.godot/imported/` y reimportar). Si igual no se ven: ¿en qué pantalla exacta? ¿es la forma de letra o color/tamaño? (Cinzel/Garamond son serif elegantes; si esperabas la pixel Press Start 2P, ver serif es lo correcto por diseño.)
2. **Narrativa**: dijiste que no te convence / dice cosas sin sentido — la revisamos mañana (recordatorio).
3. **Barra de XP**: la bajé 16px; si clipea o querés otra altura, decime el valor.
4. **Pantalla gris**: ¿implemento el precargado durante la intro mañana (cuando toquemos el intro)?

## 6. Lista "NO TOCAR sin permiso de Felipe"
- Reescritura grande de procgen / lighting / player / dungeon.
- Cambio global de iluminación; cambio de arte/tilesets; borrado de assets grandes.
- Cambios fuertes de save/load o de balance de enemigos.
- `addons/godot_ai/` (vendor/plugin).
- Implementar un sistema de fog/IA nuevo completo.
- Commits/push (los hace Felipe).
- **No testear entrando al juego por MCP** (correr/screenshot): Felipe prueba él. Solo correrlo si lo pide.

## 7. Qué leer primero un agente nuevo
1. Este archivo. 2. `architecture_notes.md` (cómo funciona cada sistema; actualizado al 2026-06-27). 3. `visibility_darkness_plan.md` (oscuridad/fog, partes viejas). 4. `code_audit_2026-06-26.md` + `cleanup_candidates_2026-06-26.md` solo como histórico (su deuda principal ya se resolvió).
5. Para arrancar: validar el caso A→B de oscuridad y el feel de combate; después la validación runtime del nav.
