# Memoria del proyecto — actualizado 2026-06-27 (para agentes/devs futuros)

> Leé esto PRIMERO antes de tocar nada. Evita repetir diagnósticos viejos y revertir fixes.
> Complementos: `architecture_notes.md` (cómo funciona cada sistema),
> `visibility_darkness_plan.md` (oscuridad/fog, ojo: tiene partes viejas), `spell_fx_plan.md`,
> `PLAN_NARRATIVO.md` / `lore/PROPUESTAS_LORE_2026-06-26.md` (intro narrativa, pendiente).
> ⚠ `code_audit_2026-06-26.md` y `cleanup_candidates_2026-06-26.md` son **snapshots del 2026-06-26**:
> su deuda dominante (god-objects `dungeon.gd`/`hud.gd`, path 2.5D/Tiled muerto, director static en Enemy)
> **YA SE RESOLVIÓ** (ver §3.bis y §4). Leelos como histórico, no como TODO vigente.

## 1. Estado actual confirmado
- **Godot 4.6**, juego isométrico 2D tipo Diablo-like / dungeon-crawler. Rama de trabajo actual: **`master`** (los refactors de §3.bis y las features de §3.ter están **commiteados y pusheados**). `iso-merge` quedó atrás y es histórico.
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
> Todo lo de abajo está commiteado/pusheado en `master`. Lo que antes este doc listaba como "god-objects a partir" y "path 2.5D muerto" **ya está resuelto**.
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

### Ronda 3 — puertas (USE_DOORS) más coherentes
- **Spawn pegado a la puerta de destino** (`dungeon_gen.gd get_door_specs`): al cruzar caías ~2 celdas adentro de la sala destino; ahora aterrizás SÓLO ~1 celda hacia adentro desde la puerta de vuelta (`land`), o sea justo al lado de ella, del lado de adentro. Salvaguarda: si el aterrizaje cae sobre la propia puerta de vuelta, se empuja 1 celda más (evita reentrar al toque).
- **Radio de activación de puerta reducido** (`door.gd`): `NEAR_DIST` 100 → **50** px. Hay que estar casi tocando la puerta para el prompt/entrada (antes se activaba de lejos).
- **Caras opuestas garantizadas** (FIX 3, documentado en `get_door_specs`): el grafo es no dirigido → cada conexión genera 2 specs (a→b y b→a); cada `from_cell` se deriva de la DIRECCIÓN entre salas, que es opuesta para a→b vs b→a → las dos puertas del par quedan en lados opuestos (NE↔SW, NW↔SE…), resuelto por `dungeon._compute_door_faces` vía `neighbor()`. No hubo que tocar el render de muros. NOTA: la orientación del player NO se forzó (player.gd recalcula `facing_dir` cada frame desde movimiento/aim, lo pisaría) — solo se resolvió la POSICIÓN del spawn.

### Ronda 4 — esquinas, colisión por-pieza, floaters UI, mobs, fachada uniforme
- **Esquinas = DOS muros sueltos** (`dungeon.gd` `CORNERS_AS_TWO_WALLS=true`, `_paint_walls`): en vez del sprite de esquina, la celda de esquina pinta sus dos bordes (trasero a IsoWallsBack, fachada a IsoWalls). La luz (óvalo) los trata bien (cada borde su span) y el reveal funciona por-borde. En la esquina NORTE el orden NE→NW deja el NW de overlay ARRIBA. (El sprite de esquina queda como branch alternativo del toggle.) Felipe va a pulir el arte; el sistema queda así.
- **Fix colisión diagonal de esquina** (`_build_iso_boundaries`): ahora chequea los **8 vecinos** (no solo cardinales) → la celda diagonal de la esquina (que tocaba el piso solo en diagonal) se bloquea → el player ya no se escapa al vacío por el pico.
- **Colisión de muro POR-PIEZA** (NUEVO, tool + juego): la `wall_origin_tool.html` tiene un modo **"Colisión"** para dibujar el polígono de colisión de cada pieza (mismas claves que el origin: `wall_nw`/`wall_ne`/…/`corner_*`), auto-guarda a `tools/rig/wall_collision.json` (coords CELL-LOCAL, mismo espacio que el occluder; endpoint `/api/wallcollision` en `serve.py`). El juego lo lee en `dungeon._install_iso_collisions` (physics layer 0 = capa 1; variantes/puertas reusan el polígono de su base). **SEGURO**: si el JSON está vacío, no cambia nada (sigue la barrera). Resuelve "variaciones (muro roto) sin colisión". OJO export: el .json en `res://tools/rig/` quizá haya que incluirlo en el preset o bakearlo.
- **Números/textos flotantes a NIVEL UI** (`floater.gd` + `game_state.floater`): van en la CanvasLayer **FX** (no en el mundo) → NO los oscurece el CanvasModulate ni las luces; siguen al punto del mundo convertido a pantalla (`get_canvas_transform`). Se ven SIEMPRE claros. **Números de daño BLANCOS** (mob + jefe; crit dorado).
- **Mobs**: tamaño **×1.3** (sprite + colisión + hitbox juntos, `enemy.gd`); **barra de vida más cerca de la cabeza**.
- **Player achicado** (`player.gd rig_scale` 0.4 → 0.36).
- **Fachada revelada UNIFORME y SIN LUZ** (`dungeon_fog.gd` + `dungeon.gd`): (1) **CanvasGroup** atómico — todas las fachadas de la sala activa se compositan en un grupo y el alpha se aplica al GRUPO (`self_modulate`) → los bordes que se solapan no se duplican (sin costuras oscuras de grosor). (2) Material **`_iso_wall_mat_reveal`** = wall shader con `light_count=0` + `ambient` fijo (0.62) → la fachada transparentada NO recibe luz (ni óvalo ni círculo del player), brillo plano uniforme. `REVEAL_ALPHA` volvió a **0.2** (bien transparente, ahora que es limpia). _spawn_wall_sprite acepta `parent`+`reveal`. El cleanup de regen (`_paint_iso`) libera el grupo.

### Dudas abiertas para Felipe (preguntar mañana)
1. **Fuentes UI**: verifiqué en headless que TODAS cargan bien (Cinzel/Garamond + LabelSettings, sin errores) y toda la UI pasa por UiTheme. NO hay bug de código. Casi seguro es **caché del editor abierto en vivo** (agregaste las fuentes hoy con Godot abierto) → cerrar y reabrir Godot (o borrar `.godot/imported/` y reimportar). Si igual no se ven: ¿en qué pantalla exacta? ¿es la forma de letra o color/tamaño? (Cinzel/Garamond son serif elegantes; si esperabas la pixel Press Start 2P, ver serif es lo correcto por diseño.)
2. **Narrativa**: dijiste que no te convence / dice cosas sin sentido — la revisamos mañana (recordatorio).
3. **Barra de XP**: la bajé 16px; si clipea o querés otra altura, decime el valor.
4. **Pantalla gris**: ¿implemento el precargado durante la intro mañana (cuando toquemos el intro)?

## 7.ter. Mecánica de DIVISOR / cuartos conectados (2026-06-29, SANDBOX — `closed_room_test.gd`)
Exploración en el sandbox (NO en el juego real todavía). Idea de Felipe (validada contra D2/BG3): NO conectar
salas lejanas con teleport, sino **una sala grande subdividida por un muro interno = dos sub-cuartos adyacentes**.
- **DIVIDER_MODE** en `closed_room_test.gd`: 0 = divisor de VACÍO (muro doble cara). 1 = fila de muros NE interna
  + cutaway + puerta. 2 = multi-divisor diagnóstico.
- **CUTAWAY ("transparencia por legibilidad", estilo D2/BG3):** el muro interno queda en su capa normal (z=-1,
  CERO y-sort); cuando el player queda DETRÁS, en vez de ocluir se **fadea** (`_process`, lado iso v vs v_mid-0.5,
  anclado a los pies). Resuelve la oclusión del muro interno sin tocar el z-order.
- **Colisión** alineada al borde NE (tira fina, no la celda entera). **Puerta** en el hueco: sprite DoorNE↔OpenDoorNE,
  CLICK (Area2D input_pickable) togglea sprite + colisión. (Falta: colisión de la puerta cerrada no bloquea — pendiente,
  va con la colisión por-pieza.)
- **Artefacto T-junction RESUELTO** (ver `architecture_notes.md` §óvalo): el divisor pegado al muro NW daba doble óvalo;
  fix = **span POR-INSTANCIA** en `wall_face.gdshader` (`use_manual_span` + `manual_span_a/b`, default off). Cada muro
  puesto a mano carga su span y NO entra a `_wall_spans_all`. Confirmado por Felipe ("SE ARREGLÓ").
- **FASE 1 INTEGRADA AL MAIN + VERIFICADA in-game (2026-06-29, Felipe: "funciona espectacular"):** módulo reusable `scripts/dungeon_dividers.gd`
  (**DungeonDividers**, lazy como gen/decor/fog). El procgen guarda `d._room_specs` (origin/w/d por sala). `dungeon.generate()`
  llama `_place_dividers()` tras `_build_iso_boundaries` → subdivide la PRIMERA sala grande (w,d≥5) con un divisor + puerta
  (eje más largo, hueco al medio). `dungeon._process()` llama `_dividers.update_cutaway(pl)`. Probado headless OK; falta que
  Felipe lo juegue.
- **FASE 2 (2026-06-29, VERIFICADA — Felipe "está todo bien"):** regla de procgen en `_place_dividers()` → **~60% de las salas** se
  subdividen (`Rng.chance(0.6)`, seedeado por piso), hueco/puerta en posición al azar (no contra el perímetro), se SALTEA
  la sala de spawn. **Puerta CERRADA**, abre con **CLIC DERECHO + proximidad** (`DOOR_NEAR=70`; el clic izq es ATACAR, por
  eso derecho). **Nav resuelto:** los muros del divisor + la puerta cerrada se marcan sólidos en el AStar de mobs
  (`_nav_solid`); abrir la puerta libera el nav. (El player no usa AStar → camina libre, lo frena solo la colisión de borde.)
- **Deuda viva:** la puerta no tiene prompt/beacon visual (Felipe tiene que saber que es clic derecho) → pulido opcional.
- **FASE 3 (2026-06-29, VERIFICADA — Felipe "perfecto ambos"):** el divisor ya NO asume el ancho prístino de la sala
  (`_room_specs`). En `add_divider`, desde la celda media (interior = piso) **crece ± a lo largo de su eje mientras
  haya piso y frena al primer vacío/borde** → cada punta queda en contacto con un muro perpendicular (perímetro,
  otra zona fusionada o borde de mapa). La puerta se recoloca a una celda INTERNA (nunca en una punta). Mata los
  divisores que "empezaban/terminaban en la nada" cuando un corredor o `_remove_thin_walls` había disuelto el
  perímetro que el extremo iba a tocar. Helper `_is_floor` (fuera de grid = muro). Puede cruzar a una sala vecina
  fusionada y dividirla también: comportamiento DESEADO (un divisor divide "zonas, cuartos, mapa entero").
- **FASE 4 — REGLA "ninguna región sin salida" (2026-06-29):** `_place_dividers` ahora PLANIFICA todos los
  divisores (`plan_divider`, no spawnea) → `ensure_connectivity(plans, spawn)` → `render_divider`. El flood-fill
  caminable parte del spawn: los muros sólidos bloquean, las **puertas NO** (el jugador las abre). Cada región de
  piso no alcanzada = sellada → se abre **un hueco** (`extra_gaps`) en un muro de su frontera (= no colocar ese
  muro; nada que borrar). Causa que atacaba: con el crecimiento, dos divisores cruzados pueden sellar un cuadrante.
  Sólo repara lo sellado por DIVISORES (el MST garantiza corredores entre cuartos).
- **FASE 5 — anti-superposición puerta/muro (2026-06-29):** `resolve_overlaps(plans)` (entre plan y connectivity):
  si la puerta cae sobre muro perimetral (`d._wall_cells`) o de otro divisor, la reubica a la celda interna limpia
  más cercana al centro; sin celda limpia → sin puerta (lo cubre la FASE 4). Y `render_divider` OMITE colocar muro
  donde ya hay perímetro (comparte el existente). Mata el bug "puerta con un tile de muro encimado" que aparecía
  al caer la puerta en una celda de borde/corredor (consecuencia del crecimiento de FASE 3).
- **Minimapa → AUTOMAP estilo Diablo II (2026-06-29):** REESCRITO de `Image` rellena a **wireframe iso de líneas**
  (`minimap.gd` + nuevo `minimap_wire.gd`/`MinimapWire`). Dibuja sólo las aristas de pared exploradas
  (`Dungeon.get_wall_edges()`) con `draw_multiline`, en el iso real (4:1). Radar circular (recorte por el shader
  sobre `_draw()`, sin SubViewport) + mapa M overlay translúcido. `MinimapWire` se carga por `preload` (no
  class_name) para no romper por orden de carga. Niebla = `cell_seen`. Ver `architecture_notes.md §3.bis`.
## 7.quater. MAPA CONTINUO (Camino "B") — EN CURSO (2026-06-29, SIN commitear → ahora pusheado)
Pivote de diseño (pedido de Felipe): se eliminan las puertas-teleport; todo es **un solo mapa caminable**
(salas + corredores + divisiones). El cambio de piso sigue siendo el **portal** en `exit_cell` (main.gd) → la
"escalera" futura es solo reskin del portal.
- **`USE_DOORS = false`** (dungeon.gd:17): el procgen ahora **talla corredores en L** (2 tiles) entre las salas
  del grafo (`_connect_rooms`→`_connect`) + `_remove_thin_walls`. Sin spawn de Door-teleport.
  - **Corredores ISO (2026-06-29, Felipe "perfecto ambos"):** `_connect` ya NO usa `carve_h`/`carve_v` (cartesianos
    → escalera dentada en grid STACKED). Descompone el delta entre centros en pasos `(u,v)` de los ejes visuales
    `ISO_AXIS_A`=SE / `ISO_AXIS_B`=SW y talla la L con `_carve_iso_leg` → tramos rectos en el plano iso. `carve_h`/
    `carve_v` quedan SOLO para `_gen_test_grid`.
- **TODOS los muros = Sprite2D con SPAN POR-INSTANCIA** (antes tiles): `_place_wall_pieces` ya no usa `set_cell`;
  cada muro lleva el span de su run (mapa `_wall_span_map` que arma `_merge_wall_spans`, llamado ANTES de
  `_paint_walls`). Mata el artefacto de óvalo en las uniones T de corredores/esquinas/divisores (unificado).
  Reveal NO se tocó (las fachadas ya entran como kind:1 sprites). **Perf OK** (Felipe lo verificó: ~1500-2000
  sprites aguantan). Deuda: `_update_wall_span_uniforms` global quedó sin uso (inofensivo).
- **CUTAWAY POR-MURO** (`_update_wall_cutaway` en dungeon.gd, REEMPLAZA el reveal por-sala): cada frame
  transparenta las FACHADAS que TAPAN al player (sala o corredor), + sus vecinas pegadas (1 anillo `CUT_NEIGHBORS`)
  para un patch suave. Índice `_front_walls` (cell→[holder]); test `_wall_covers` (silueta CUT_HW/H/FOOT, tuneable).
  Resuelve "no me veo en corredores" + "salí de la sala y una punta me tapa". Sin CanvasGroup → ojo doble-alpha
  en solapes (a vigilar; si molesta, reincorporar). Verificado por Felipe que anda.
- **PENDIENTE (issue 3):** regla de procgen → una línea de muros con PUERTA debe terminar en muro/esquina, no en
  un agujero/piso (si no, rodeás la puerta y no tiene sentido). Próximo paso.
- **Camino "B" puro** (salas separadas + flood-fill de visibilidad) ya no aplica: vamos por mapa continuo real.

## 7.quinquies. COLISIÓN de muros (sprites) + ESQUINAS dedicadas + PUERTA multi-poly (2026-06-29, SIN commitear)
Al pasar TODOS los muros a sprites (mapa continuo), los tiles dejaron de dar colisión → se reconstruyó:
- **`dungeon._install_wall_collisions()`** (corre tras `_build_iso_boundaries`): instala los polígonos de
  `wall_collision.json` como `CollisionPolygon2D` en el `_iso_bounds` único. **MERGE POR RUN**: agrupa por
  `(side, endpoint)`, infla 0.5px (`Geometry2D.offset_polygon`) y `merge_polygons` iterativo → colisión
  **continua** por muro (no te enganchás entre tiles al caminar pegado). Verificado por Felipe que la fluidez quedó bien.
- **Divisores** (`dungeon_dividers._add_wall_collision`): ahora usan `wall_ne`/`wall_nw` del JSON (antes tira fina hardcoded).
- **VARIANTES-CORNER** (sistema nuevo, OPT-IN, FALTA EL ARTE de Felipe): 8 piezas `wall_xx_corner_yy` (2 por
  esquina N/S/E/O) en `assets/iso/walls/corner_variants/` (PNGs 144×200, dir creado vacío). `_ensure_corner_variants`
  las registra si el PNG existe; `_paint_walls` swapea el muro normal por la variante en celdas con par adyacente;
  `_install_wall_collisions` usa sus polígonos `wall_xx_corner_yy` (complementarios → cubren el VÉRTICE). Si falta
  PNG o polígono → **fallback automático** al wall normal (nada se rompe). El "verde triangular" en el debug de
  esquina = solape de runs SE/SW (inofensivo, da fluidez); el HUECO del vértice lo cierran estas variantes.
- **PUERTA multi-poly**: `wall_collision.json` ahora soporta SINGLE `[[x,y]…]` o MULTI `[[[x,y]…],[…]]`. Loader
  (`_parse_poly_pts` / `_install_wall_collisions`) y `dungeon_dividers` iteran N polígonos. `open_door_ne/nw` ya
  dibujados (2 marcos c/u en el JSON) → puerta abierta bloquea los costados, pasás por el hueco.
- **TOOL** (`wall_origin_tool.html`): tab Colisión con **multi-polígono** (lista de polys + "+ Nuevo polígono" /
  "− Borrar"), **"Mostrar partner"** (dibuja la pieza compañera de esquina como guía azul), y 8 slots corner + 2 open_door.
- **CUTAWAY**: histéresis asimétrica (prender 0.4 / apagar 0.05, mata flicker al cruzar tiles) + gate usa `body.y`
  no `pp.y` (no se apaga al pegarte al muro). Alpha = 0.5 (muros y divisores).
- **PENDIENTE de Felipe (arte/tool):** dibujar los 8 PNGs de `corner_variants/` + sus polígonos en el tool →
  cierra el hueco del vértice. (Sin eso, todo funciona con fallback.)

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
