# Auditoría de código — 2026-06-26 (hito de cierre/limpieza)

## Resumen ejecutivo
Auditoría profunda read-only del juego (Godot 4.6, dungeon-crawler iso) con 4 subagentes en paralelo por
área. El proyecto **abre y es producción** (`main.tscn`, `use_test_map=false`). El hallazgo estructural
dominante: **coexisten 3 sistemas de muros** — el iso vivo (WallSegment + capas IsoWalls/IsoWallsBack),
un path **2.5D entero muerto** (~600 líneas, no corre con `ISO=true`), y 2 scripts huérfanos
(`iso_procgen.gd`, `iso_wall_occluder.gd`) de sandbox. `dungeon.gd` (1875 líneas) y `hud.gd` (739) son
god-objects. Hay **1 bug que afecta gameplay hoy** (nav marca piso-con-muro como sólido) y varios riesgos
de perf por la migración reciente de oscuridad/IA. Se aplicaron solo cambios chicos y seguros; todo lo
riesgoso quedó documentado.

## Estado inicial del repo
- Fecha/hora: **2026-06-26 ~01:14**. Rama `iso-merge`. Último commit `4c3710c` (habitaciones iso + procgen + debug regen).
- **Todo el trabajo de esta sesión está SIN COMMITEAR** (12 scripts modificados + archivos nuevos: `door.gd`, `health_bar.gd`, `visibility_manager.gd`, `boss_bar_fill.gdshader`, assets de boss/hud/walls, docs). Ver `git status`.
- Main scene = `scenes/main.tscn`. Autoloads: Rng, GameState, Data, Items, Audio, LightCfg, LightField, SaveSystem, Fps, + `_mcp_game_helper` (vendor).

## Estado general del proyecto
Sólido y jugable, pero con **deuda de transición**: la migración reciente (oscuridad estilo D2, puertas,
IA de mobs, luz de mobs, todo de esta sesión) está implementada y razonablemente limpia, pero dejó
inconsistencias con la documentación y un par de acoplamientos. La base iso (procgen + muros + reveal +
luz) funciona; el ruido viene del 2.5D legacy nunca borrado y de `dungeon.gd` haciendo demasiado.

## Riesgos principales (priorizados)
1. **[ALTA] Bug de nav** — `dungeon.gd` `_build_iso_nav` marca como sólidas las celdas de `_iso_walls`/`_iso_walls_back`, pero los muros se pintan en la **celda de piso interior** → esas celdas de piso quedan no-navegables. Síntoma: mobs evitan bordes/esquinas de salas. **Afecta gameplay hoy** y a la IA nueva. (NO se fixeó: cambia comportamiento, sin runtime test. Ver Recomendaciones.)
2. **[ALTA] 3 sistemas de muros coexistiendo** — confunde y multiplica superficie de bug. El 2.5D (~600 líneas) está muerto con `ISO=true`.
3. **[ALTA] `dungeon.gd` god-object** (1875 líneas): grid+grafo+roles+Tiled+TileSet-gen+pintado iso+pintado 2.5D+nav+colisión+antorchas+cielo/ventanas+reveal+fog. Partición propuesta abajo.
4. **[ALTA] `hud.gd` god-object** (739): HUD + inventario HD por código + tienda completa + pausa + muerte + animación. 
5. **[MEDIA] Visibilidad de mobs con doble criterio + doc desactualizada** — `enemy.gd` auto-gatea por **distancia** (disco px), no por celda/LOS; la rama `vis_threat` del manager quedó muerta; el boss nunca se oculta. `docs/visibility_darkness_plan.md` describe el comportamiento viejo.
6. **[MEDIA] Perf de la migración** — `_update_visibility` alocaba dict/frame (corregido a `.clear()`); cada mob tiene un `PointLight2D` nativo (no entra al pool de LightField, pero sí cuesta render 2D — acotado por sleep+visibilidad); `LightField.pack_lights` corre cada frame.

## Sistemas más frágiles (tocar con test visual)
- **Iluminación**: el modelo de luz (falloff² + cap preservando tono) está **triplicado** (`LightField.sample`, `wall_face.gdshader`, y el push de uniforms) — cambiar uno exige sincronizar los otros. `cap=1.4` es número mágico en 4 lugares.
- **Fog/visibilidad**: `_update_visibility`/`_update_room_reveal` están **anidados dentro de `_update_iso_wall_mat()`** → si `_iso_wall_mat_solid` fuera null, la niebla se congela en silencio. Hoy funciona (siempre no-null en iso).
- **Reveal de fachada**: tweens de `_reveal_tw` **no se matan** en regen de piso → posible callback sobre nodos liberados al encadenar pisos rápido.
- **Antorchas de procgen**: `_place_torches` asume salas **cartesianas** (rect bbox) → en salas iso (paralelogramos) las antorchas quedan mal ubicadas. El sandbox usa `spawn_wall_torch` por-borde (correcto) pero el procgen real no.

## Cambios SEGUROS realizados esta noche (mínimos, behavior-neutral)
1. `dungeon.gd`: print `[walls] segmentos=` gateado tras `const DEBUG_LOG := false`.
2. `dungeon.gd`: docstring de clase reescrito (decía "2.5D estilo Pixi / FLAT_MODE" inexistentes → ahora describe el path iso real).
3. `dungeon.gd`: `_update_visibility` usa `_visible_now.clear()` en vez de alocar `{}` cada frame (perf, idéntico).
4. `enemy.gd`: al dormir (`_sleeping=true`) se setea `visible=false` → oculta render + aura del mob lejano (cubre el caso de alejamiento brusco por teleport de puerta, que dejaba la lucecita prendida).
5. `main.gd`: `clampi` anti-crash en `zone_idx` (`_build_floor`) → un save corrupto/futuro con `zone_idx` fuera de rango ya no crashea el indexado de `Data.ZONES`.
6. `lighting_debug.gd` / `speed_debug.gd`: paneles de tuning (teclas **L** y **V**) gateados tras `OS.is_debug_build()` → ocultos en release; el **post-FX de luz sigue corriendo siempre** (solo se gatea el panel de sliders).
7. `pickup.gd` y `main.gd`: comentarios stale corregidos (XP "red ya está"; aclarado el rol del visibility_manager).
8. **`dungeon.gd` `_build_iso_nav`: FIX del bug de nav (con OK explícito de Felipe).** Removidas las 2 vueltas que solidificaban las celdas de piso del perímetro → los mobs ahora pueden rutear hasta los bordes/esquinas de las salas. Parsea OK (verificado por reimport MCP). **PENDIENTE validación runtime de Felipe:** que los mobs lleguen a los bordes y NO atraviesen muros (la colisión la da `_build_iso_boundaries`, aparte del nav).

## Cambios NO realizados por riesgo (documentados como recomendación)
- **Bug de nav** (`_build_iso_nav`): ✅ **APLICADO** (con OK de Felipe) — ver "Cambios SEGUROS" #8. Pendiente solo la validación runtime.
- **Borrar** legacy/huérfanos y sandbox → solo listados en `cleanup_candidates_2026-06-26.md`.
- **Partir `dungeon.gd`/`hud.gd`** → reescritura mediana; ver Recomendaciones.
- **Unificar visibilidad de mobs** (sacar el `visible=` de enemy.gd y meter mobs/boss en un único gateo) → cambia comportamiento; documentado.
- **Reescribir `_place_torches`** a por-borde iso → cambio visual; documentado.

## Bugs sospechosos (con evidencia)
- `dungeon.gd` `_build_iso_nav` — piso-con-muro marcado sólido (gameplay). **[ALTA]**
- `dungeon.gd` `_paint_iso` no mata `_reveal_tw` → callbacks sobre sprites liberados al regenerar. **[MEDIA]**
- `enemy.gd` — telegraph (WINDUP rojo) puede quedar invisible si llegan **daños encadenados** (cada `take_damage` re-arma `flash_t` blanco; el telegraph solo se repinta al llegar `flash_t` a 0). **[MEDIA, feel]**
- `enemy.gd`/`take_damage` — `path_grid.is_cell_seen/visible` **crashea** si `path_grid` fuera `iso_procgen` (no tiene esos métodos). En `main` es `Dungeon` → no pasa; mina solo en sandbox. **[BAJA]**
- `dungeon.gd` `_gen_grid` — cota Y del origen de sala mal dimensionada (mezcla ancho con profundidad) → salas grandes fallan más, baja ROOM_COUNT efectivo. **[MEDIA]**
- `light_field.gd` `sample()` — `_amb_node` puede quedar de otra escena tras cambio (hay fallback). **[BAJA]**

## Recomendaciones para mañana — backlog priorizado (merge de las 2 olas)
**Robustez (antes de seguir features):**
1. **Save atómico + no borrar la run en silencio** (`save_system.gd` `_write`/`_read`): `.tmp`+rename, y distinguir corrupto vs ausente. Es el riesgo más alto de perder progreso. (zone_idx ya clampeado.)
2. ✅ **Bug de nav APLICADO** esta noche (`_build_iso_nav`) — solo falta tu validación visual (mobs llegan a bordes/esquinas y NO atraviesan muros).

**Validación/feel (con vos probando):**
3. **Validar caso A→B de oscuridad** + feel de combate (telegraph/slots/auras), tunear knobs (tecla L: Jugador/Mobs/Ambiente).
4. **Boss**: contacto sin `hit_cd` (DPS desbalanceado) + tope de summon que cuenta mobs ajenos (puede invocar 0). Decisiones de balance → las definís vos.

**Limpieza (riesgo bajo, gran reducción de ruido):**
5. **Borrar el bloque sandbox** (3 escenas test + scripts iso_* + huérfanos `bossbar`/`window_sky`/`_autowalk`/`vignette`). Ver cleanup doc.
6. **Borrar el path Tiled + 2.5D muerto** (~600 líneas en dungeon.gd + maps/*.tmx + design.tsx): confirmado muerto Y roto bajo `ISO=true`.
7. **Audio muerto**: cablear o borrar `skel_death.mp3` / `attack`(swing.wav) / `coin2-3.wav` / `boom-cast.m4a`.

**Arquitectura (cuando haya aire):**
8. Unificar visibilidad de mobs/boss en el manager (hoy mobs se auto-gatean por distancia, boss no se gatea).
9. Partir `dungeon.gd` (1875) y `hud.gd` (739) — ver `architecture_notes_2026-06-26.md`.
10. Mover el director de combate de `enemy.gd` (static) a un autoload propio; extraer helpers de material UNSHADED / texturas radiales (duplicados ×3-5).

## Comparación con buenas prácticas (ARPG iso / Diablo / BG3 / indie Godot)
- **Generador como god-object**: común en prototipos; la industria separa *generación* (grid/grafo) de *spawning* y de *render/pintado*. Acá `dungeon.gd` mezcla las tres + presentación. Partir es estándar.
- **Director de combate** (máx atacantes + slots): patrón correcto y reconocido (lo usan ARPGs y character-action games). Bien encaminado; moverlo a un autoload propio lo haría testeable.
- **Oscuridad = luz, exploración = memoria**: el enfoque adoptado (D2: el mundo se ilumina por luces, el mapa recuerda) es el correcto. La desviación actual (mobs gateados por disco de distancia, no por celda/LOS) es aceptable como paso pero conviene unificar y respetar paredes a futuro (shadowcasting).
- **Modelo de luz triplicado**: la industria mantiene UNA fuente (shader) y deriva el resto; tres copias GDScript/GLSL es deuda. Aceptable mientras se sincronicen a mano, pero frágil.
- **CanvasGroup para el rig del player**: buena decisión (atomicidad contra muros). Solo limpiar los comentarios que describen un z-order per-sprite que el CanvasGroup ya no permite.

## Qué revisó cada subagente (conclusiones principales)
- **Agente A (dungeon/procgen/muros)**: 3 sistemas de muros coexistiendo; ~600 líneas 2.5D muertas; bug de nav (piso-con-muro sólido); `_place_torches` cartesiano en mundo iso; partición propuesta de `dungeon.gd`.
- **Agente B (luz/fog/shaders)**: modelo de luz triplicado + `cap` mágico ×4; rama `vis_threat` muerta; doble fuente de visibilidad de mobs (distancia vs celda) + boss nunca oculto; `_update_visibility` aloca dict/frame; fog acoplado al material de muros; riesgos de perf. (Su temor de MAX_LIGHTS por auras de mob se **corrigió**: las auras NO entran al pool de LightField — solo cuestan render 2D nativo, acotado.)
- **Agente C (player/enemy/HUD)**: el director de combate libera bien en los 3 caminos (sin leak); `bossbar.gd` huérfano; `hud.gd` god-object; comentarios de z-order del player desfasados del `CanvasGroup`; telegraph borrable por flash encadenado; glow del mob no se apagaba al dormir (corregido).
- **Agente D (inventario/cleanup)**: confirmó producción vs sandbox con refs; huérfanos `bossbar`/`window_sky`/`_autowalk`/`vignette.tres`; 22 tilesets `iso_dungeon*` chatarra; `*_frames.tres` de mobs se cargan por string → NO son huérfanos.

## ¿El juego corre?
**SÍ — verificado vía MCP de Godot (editor conectado, 4.6.3).** Se re-importaron 13 scripts editados y
**ninguno dio error de parser** salvo un caso explicado abajo. El gameplay no se runtime-testeó (Felipe prueba).

### ⚠ Artefacto del editor a saber (NO es un bug de código)
El editor muestra un **Parse Error STALE** en `scripts/main.gd:58` (`Cannot infer the type of "vm"`).
**El disco está correcto** (verificado con `read_text` del propio Godot Y con lectura directa: la línea es
`var vm = load(...)` con `=`, sin `:=` — no hay inferencia, no hay error). El editor parsea una versión vieja
porque **tiene `main.gd` abierto en una pestaña con el texto anterior** (`:=`, de antes del fix de esta sesión).
- **Acción mañana:** en el editor, recargá `main.gd` (click derecho en la pestaña → *Reload*, o cerrá/reabrí,
  o reiniciá el editor). **NO le des Ctrl+S a esa pestaña vieja** o pisás el fix en disco con el `:=`.
- El juego **compila desde disco** al darle Play → corre bien aunque el editor muestre el error.

### Otro warning pre-existente (no tocado)
`UID duplicate` entre `docs/index.*` y `build/web/index.*` (el export web vive duplicado en `docs/` para
Pages). Pre-existente, no es de esta sesión. Si molesta, unificar el deploy; no lo toqué (riesgo en build/deploy).

---

# 2ª ola de auditoría (persistencia, combate/boss, periféricos)

Tres agentes más sobre superficie no cubierta. Hallazgos nuevos (los seguros ya se aplicaron; ver "Cambios seguros" arriba, actualizado).

## Persistencia / flujo (Agente E)
- **[ALTA] Save no-atómico + sin detección de corrupto** (`save_system.gd:44-47` `_write`, `:55` `_read`): un crash a mitad de `store_string` (autosave c/8s + en cada transición) deja el JSON truncado; `_read` lo trata como "no hay save" y **borra la run en silencio**. NO tocado (saves están en la lista "no tocar sin permiso"). **Fix recomendado:** escribir a `.tmp` + rename atómico; en `_read` distinguir corrupto (warn + backup) de ausente.
- **[ALTA] `zone_idx` fuera de rango crasheaba** (`main.gd` `_build_floor`): **CORREGIDO** con `clampi` anti-crash. (`next_floor` ya estaba cubierto por su guard de victoria.)
- **[ALTA] `hash([run_seed, depth])` no es estable entre versiones/plataformas de Godot** (`main.gd`): un upgrade del engine puede regenerar otro mapa para el mismo save. **Recomendación:** mezclador explícito (`run_seed * 2654435761 + depth`), no `hash()` de Array. NO tocado (cambia seeds → sensible).
- **[MEDIA] Fuga de regen determinista** (`main.gd` `_debug_regen`/force_new): el nuevo `run_seed` se saca del RNG ya sembrado con el `floor_seed` anterior → la *secuencia* de regens es reproducible. (No es "mismo mapa cada vez" — cada press da uno distinto — pero la secuencia es determinista.) Documentado, NO tocado (seed sensible).
- **[MEDIA] Sin validación de versión de save** ni de `floor_in_zone`; `player.load_save` mete `equip`/`bag` crudos (item con schema viejo podría romper `_weapon_type_data`). NO tocado.
- **[ALTA, candidato a borrar] Path Tiled CONFIRMADO muerto Y roto:** `maps/floor_01.tmx`/`floor_02.tmx` existen pero `USE_FIXED_MAPS=false` → nunca se llama; y `generate_from_tiled` pinta con `_paint()` (2.5D legacy, no corre con `ISO=true`) sin nav/colisión iso. Todo el subsistema Tiled+2.5D es borrable. Ver cleanup doc.
- **[MEDIA] `game_state.gd` god-autoload:** señales + estado de run + spawn de floaters/pickups + **toda la tabla de loot** (`drop_loot`). Separar `LootSystem`/spawner a futuro.
- **[MEDIA] `next_floor` sin guard de transición:** posible doble-encolado de `next_floor.call_deferred()` en piso normal (exit abierto durante el frame diferido). Recomendación: flag `_transitioning` síncrono.

## Combate / boss / proyectiles (Agente F)
- **[ALTA] Tope de summon del boss cuenta TODOS los Enemy del piso** (`boss.gd:220-223`), no solo sus minions → en un piso poblado el jefe puede invocar **0**. Recomendación: grupo `boss_minion` o contador propio. NO tocado (lógica de boss).
- **[MEDIA, balance] Daño de contacto del boss SIN `hit_cd`** (`boss.gd:146-147`): pega cada frame de física (los mobs tienen `hit_cd=0.5`) → DPS de contacto desbalanceado. NO tocado (balance → necesita confirmación).
- **[MEDIA] Minions del boss no se limpian al morir el jefe** (solo en el próximo `_build_floor`). Quirk de diseño.
- **[MEDIA] Colisión de proyectil partida** (`projectile.gd:96-134`): raycast (máscara fija 1) + señal `body_entered` (máscara real) → posible doble `_impact` (2 explosiones+luces). Unificar.
- **[MEDIA, perf] `cast_shadow._process` por entidad por frame sin gate de visibilidad/sleep** (`cast_shadow.gd:124-212`): hasta 4 luces × 7 uniforms por entidad. Los mobs ocultos igual computan (los hijos de nodo invisible no renderizan pero sí corren `_process`).
- **[MEDIA] Duplicación**: material UNSHADED en 5 archivos; gen de textura radial en 3; lookup de tier de staff triplicado; loot partido entre `game_state.drop_loot` y `chest.gd`. Candidatos a helpers compartidos.

## Periféricos (Agente G)
- **[MEDIA, release] Paneles debug L (luz) y V (velocidad) sin flag** → expuestos en release. **CORREGIDO:** gateados tras `OS.is_debug_build()` (el post-FX de luz sigue corriendo siempre; solo se gatea el panel de sliders).
- **[MEDIA] Audio muerto:** `"attack"→swing.wav` cargado pero nunca reproducido (el mago no tiene melee); `skel_death.mp3` sin uso (todo enemigo suena `enemy_death`=rata, `enemy.gd:441`). `coin2/coin3.wav` y `boom.m4a`/`cast.m4a` (fuentes viejas) sin uso. Cablear o borrar.
- **[BAJA] `fps_counter` arranca VISIBLE** (sin `visible=false` en `_ready`) → FPS en pantalla en release. Toggle F3. Ocultar por defecto para el build final. NO tocado (es lo que ves hoy; preferencia tuya).
- **[BAJA] `lighting_debug`/`speed_debug` NO son borrables** pese al nombre (`lighting_debug` ES el post-FX real). Conservar.
- **[BAJA] Stats de la card del menú hardcodeados** (`menu.gd:129`); TODO informal en `sky_dragon.gd:16`.
