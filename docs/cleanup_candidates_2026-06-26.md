# Candidatos a limpieza — 2026-06-26

> **NADA de esto se borró.** Es una lista con evidencia para que Felipe decida. Verificado con búsqueda
> de referencias en todo el repo (excl. `addons/godot_ai/`, que es vendor). Main scene confirmada =
> `scenes/main.tscn`. Borrar siempre a Papelera, y de a un grupo, verificando que el juego siga abriendo.

## Borrado seguro inmediato (0 referencias, riesgo BAJO)

| Archivo | Estado | Evidencia | Recomendación |
|---|---|---|---|
| `scripts/bossbar.gd` | huérfano | sin refs en `.tscn`/`.gd`; la barra de jefe vive en `hud.gd` (BossBarFill + `shaders/boss_bar_fill.gdshader`) | borrar |
| `scripts/window_sky.gd` (`WindowSky`) | huérfano | sin refs (solo su `class_name`); nadie instancia `WindowSky` | borrar |
| `scripts/_autowalk.gd` | huérfano | sin refs en código ni escenas (nodo de debug ya borrado) | borrar |
| `assets/iso/vignette.tres` | huérfano | sin refs | borrar |

## Sandbox / escenas de prueba (no son producción; riesgo BAJO borrar el bloque)

| Archivo | Estado | Evidencia | Recomendación |
|---|---|---|---|
| `scenes/iso_test.tscn` | sandbox | no referenciada por producción (standalone) | mover a `scenes/test/` o borrar |
| `scripts/iso_procgen.gd` | sandbox | solo `iso_test.tscn:9`; reimplementa procgen+nav que ya están en `dungeon.gd` | borrar con `iso_test` |
| `scripts/iso_mob_spawner.gd` | sandbox | solo `iso_test.tscn:7` | borrar con `iso_test` |
| `scripts/iso_wall_occluder.gd` | sandbox/legacy | solo `iso_test.tscn:6`; referencia `iso_dungeon_v8.tres` (inexistente) | borrar con `iso_test` |
| `scenes/light_test.tscn` + `scripts/light_test.gd` | sandbox | no referenciada por producción | mover a `scenes/test/` o borrar |
| `scenes/closed_room_test.tscn` + `scripts/closed_room_test.gd` | sandbox | solo en comentarios de `dungeon.gd` | mover a `scenes/test/` o borrar |

> ⚠️ OJO: `dungeon.gd`, `torch.gd`, `wall_segment.gd` aparecen dentro de esas escenas de test **pero son
> producción** (se usan en `main.tscn`/`dungeon`). NO borrarlos.

## Tilesets / assets viejos (riesgo BAJO-MEDIO; verificar `iso_pixel.tres` antes)

| Archivo | Estado | Evidencia | Recomendación |
|---|---|---|---|
| `assets/iso/iso_dungeon.tres` + `_v2`…`_v20` (~21 tilesets) | chatarra de iteración | el juego solo usa `iso_pixel.tres` (`dungeon.gd:70`); `v8` solo en un comentario | borrar (verificar 1 por 1 que no estén en `.tscn` abiertas) |
| `assets/iso/floor_256x128.png`, `floor_iso.png`, `wall_floor_combo.png` | revisar manual | solo usados por los `iso_dungeon_v*` muertos | borrar SI se borran los v* **y** `iso_pixel.tres` no los referencia |

## Código muerto DENTRO de archivos de producción (NO borrar archivos; limpieza interna futura)

| Ubicación | Estado | Evidencia |
|---|---|---|
| `dungeon.gd` path 2.5D completo: `_paint`, `_spawn_face`, `_make_top`, `_make_tall_brick`, `_make_floor_ao`, `_clear_faces`, vars `_face_*/_ao_*`, consts `ROW_*/*_VARIANTS` | muerto con `ISO=true` | `generate()` retorna antes (`:182`); solo `generate_from_tiled` toca `_paint`. ~600 líneas |
| `dungeon.gd:_darken()` | muerto | nunca llamada |
| `dungeon.gd` `_room_facade` / `_room_corners` | estado muerto | se resetean pero nunca se escriben/leen |
| `dungeon.gd` `ROOM_MIN`/`ROOM_MAX` | consts sin uso | iso usa `iso_room_width/depth` |
| `wall_segment.gd` `source_id`, `is_facade`, `enum VisualState`, `is_back()` | vestigial | se setean/declaran pero no se leen en el path vivo |
| `visibility_manager.gd:32-33` rama `vis_threat` | muerta hoy | ningún mob entra a `vis_threat` (los mobs se auto-gatean en `enemy.gd`); el manager solo gatea objetos sticky |

## Confirmados por la 2ª ola de auditoría

| Archivo/sistema | Estado | Evidencia | Riesgo de borrar | Recomendación |
|---|---|---|---|---|
| **Path Tiled completo:** `maps/floor_01.tmx`, `maps/floor_02.tmx`, `maps/design.tsx` + `_load_tiled`/`_parse_tmx`/`_parse_tmj`/`_spawn_fixed_markers`/`_fixed_map_for_floor` + consts `T_*` | muerto Y roto | `USE_FIXED_MAPS=false` → nunca se llama; y `generate_from_tiled` pinta con `_paint()` 2.5D (no corre con `ISO=true`), sin nav/colisión iso | medio | borrar (parte del bloque 2.5D; verificar que no haya plan de re-activar Tiled) |
| `assets/sfx/skel_death.mp3` | muerto | `enemy.gd:441` siempre reproduce `enemy_death` (=rata) sin distinguir tipo | bajo | borrar o cablear por tipo |
| `audio.gd` key `"attack"` + `assets/sfx/swing.wav` | muerto | sin `Audio.play("attack")` en el repo (el mago no tiene melee) | bajo | borrar entrada + WAV |
| `assets/sfx/coin2.wav`, `coin3.wav` | muerto | sin key en el dict ni referencia (solo `coin.wav` se usa) | bajo | borrar |
| `assets/sfx/boom.m4a`, `cast.m4a` | fuente vieja | ya convertidos a `.wav`; los `.m4a` quedaron | bajo | borrar (fuente) |

## Otros

| Ítem | Estado | Evidencia | Recomendación |
|---|---|---|---|
| input action `nova` (`project.godot:99`) | sin uso | sin refs en scripts | revisar (¿habilidad planeada?) — bajo riesgo quitar |
| `lighting_debug.gd`, `speed_debug.gd` | **producción/debug útil** | montados en `main.tscn`; `lighting_debug` ES el post-FX real | **conservar** (no son borrables pese al nombre) |
