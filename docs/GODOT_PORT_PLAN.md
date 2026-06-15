# Cárcel del Cuteo → Godot — Plan de reimplementación

Reimplementación del roguelike web `freelance/la-carcel-del-cuteo` (HTML5 Canvas + JS)
en este proyecto Godot 4.6 (`Godot Cuteos Cript`).

## Decisiones (2026-06-14)

- **Enfoque: Reimaginar con Godot.** El juego original es la spec de diseño/balance,
  no se copia código. Se reconstruye con idioms de Godot (escenas, señales, recursos)
  y se mejora luz / UI / feel donde convenga.
- **Colisión / IA / físicas: nativo de Godot.** `CharacterBody2D` + `move_and_slide`,
  colisión desde `TileMapLayer`, pathfinding con `NavigationServer2D` / `AStarGrid2D`.
  La IA del original (chaser/erratic/shooter, BOSS_PATTERN_HANDLERS) es referencia de
  comportamiento.

## Original como referencia (qué replicar de diseño)

- TILE = 16 px de mundo. Mazmorras procedurales 64×64.
- Proyectiles 2.5D: colisión en plano (x,y), `z` = altura visual (sprite hijo offset -z).
- Contenido data-driven en `js/data.js`: CLASSES, WEAPON_TYPES, MATERIALS, RARITIES,
  SLOTS, ENEMIES, BOSSES, ZONES, UPGRADES, BALANCE → portar como `Resource`/datos Godot.
- Run = 3 zonas × 2 pisos + jefe. Pisos persistentes (schema `carcel_run_v1`).

## Arquitectura Godot objetivo

- Autoloads (singletons): `GameState`, `Data`, `Audio`, `Rng` (seedable).
- Eventos del juego vía **señales**, no flags globales.
- Pixel art: import filtro `Nearest`, cámara `zoom` entero.
- Iluminación: `Light2D` + `CanvasModulate` (pisos oscuros/embrujados) + glow de
  `WorldEnvironment`. Reemplaza el motor diferido de Pixi y las "sombras PRO" custom.
- Partículas/FX: `GPUParticles2D`.
- Persistencia: `user://` en vez de `localStorage`.

## Fases

- **F0 — Cimientos**: carpetas, autoloads, InputMap, presets de import, cámara. Portar data.
- **F1 — Esqueleto jugable**: sala hardcodeada + jugador con colisión + cámara que sigue.
- **F2 — Mazmorras**: generador procedural → pintar `TileMapLayer`, salas, pasillos, props, spawns.
- **F3 — Combate core**: ataque/energyblast, maná, dash, proyectil 2.5D, daño/ifr/knockback,
  números de daño, crítico. 1 enemigo (chaser con NavigationAgent2D).
- **F4 — Enemigos & IA**: erratic, shooter, LOS, aggro/leash/wander, élites, variedad desde data.
- **F5 — Jefes**: máquina de estados + patrones (chase/burst/spread/charge/kickball/summon),
  arena, fase 2 (enrage), barra de jefe.
- **F6 — Items & progresión**: loot, equipo, stats, drops, mejoras al subir nivel.
- **F7 — UI/HUD**: barras, inventario con tooltips/comparación, tienda, pausa, menú, final, minimapa.
- **F8 — Contenido/assets**: import masivo, animaciones (héroe 8-dir, mobs, jefe rugby), tilesets, audio.
- **F9 — Luz & polish**: Light2D, glow, partículas, screen-shake.
- **F10 — Persistencia & meta**: guardado de run en `user://`, récords, pisos persistentes.

## Estado

- [x] F0 — autoloads (Rng, GameState, Data), InputMap (WASD+flechas+mouse, 11 acciones),
      filtro de texturas Nearest. (2026-06-14)
- [x] F1 — escena `res://scenes/main.tscn`: sala 320×224 (Floor + Walls StaticBody2D),
      Player CharacterBody2D con move_and_slide + Camera2D (zoom 3). Corre sin errores. (2026-06-14)
- [x] F2 — Mazmorras procedurales: `scripts/dungeon.gd` (TileMapLayer que construye su
      TileSet placeholder en código, colisión nativa en muros). 14 salas + pasillos en L
      de 2 de ancho. `scripts/main.gd` genera y ubica al jugador en la 1ª sala. (2026-06-14)
- [x] F3a — Combate: jugador con dash (i-frames+cd), ataque energyblast (proyectil 2.5D
      `scenes/projectile.tscn` + `scripts/projectile.gd`), maná con regen. Capas: world=1,
      player=2. Proyectil frena en muro vía raycast (sin frame de solapamiento). (2026-06-14)
- [x] F3b — Enemigo chaser (`scenes/enemy.tscn`+`scripts/enemy.gd`) con NavigationAgent2D
      (nav layer en el TileSet del piso). Daño bidireccional: proyectil→enemigo (mask capa 3),
      enemigo→jugador por contacto (i-frames+knockback). Floaters de daño (`scenes/floater.tscn`,
      helper `GameState.floater`). Player con hp/take_damage/muerte. Capas: world=1, player=2,
      enemy=3. Verificado por eval (nav, daño, sin leaks). (2026-06-14)
- [x] F4 — IA completa. Aggro híbrido (sala/proximidad, persigue, leash, deambula).
      Data-driven desde `Data.ENEMIES`/`Data.ZONES` (portadas de data.js). 3 IAs: chaser,
      erratic (zigzag), shooter (kite + dispara proyectil enemigo). Élites (×1.5 hp, ×1.3 dmg/tamaño,
      tinte dorado). Proyectil genérico friendly/enemy. Color-code por IA. Verificado por eval. (2026-06-14)
- [x] F5 — Jefes. `scenes/boss.tscn`+`scripts/boss.gd`: máquina de estados que cicla
      patterns (chase/charge/burst/spread/summon) desde `Data.BOSSES`. Enrage (2ª fase) al 50%
      hp (×1.3 spd, cadencia ×1.4). Barra de jefe (`scripts/bossbar.gd` en HUD CanvasLayer).
      Proyectiles enemigos + invocación de esbirros. Verificado por eval. PENDIENTE: pattern
      kickball (rugby, requiere entidad pelota); arena dedicada + encuentro al cerrar zona (en F10).
      Test temporal: `DEBUG_BOSS` en main.gd spawnea El Liche en la última sala. (2026-06-14)
- [~] F6 — Progresión. HECHO: drops al matar (`scenes/pickup.tscn`+`scripts/pickup.gd`:
      moneda/XP/corazón/poción, prob. desde BALANCE), recolección por contacto, XP/subir de
      nivel, panel de mejora con pausa (`scripts/hud.gd` + nodos en HUD), 1 de 3 mejoras
      (Data.UPGRADES) que aplican stats (vida/daño/spd/crit/atkspd/def). HUD con stats+monedas+
      pociones. Crítico y defensa en el combate. Pociones (Q). Verificado por eval.
      PENDIENTE (va con F7): sistema de ítems con rarezas/materiales/mods + equipo + inventario. (2026-06-14)
- [~] F7 — UI/ítems. F7a HECHO: sistema de ítems (`scripts/autoload/items.gd` + tablas en Data:
      RARITIES/MATERIALS/SLOTS/WEAPON_TYPES/ARMOR_BASES/MODS/STAFF_NAMES). Generación con
      rareza/material/mods/nombres. Equipo en `Player.equip` (stats = base+mejoras+equipo, ataque
      según arma). Auto-equip si es mejor (viejo→bolsa). Drops de ítems (13% enemigos, raro
      garantizado en jefes) vía pickup "item" coloreado por rareza. Verificado por eval.
      F7b HECHO: pantalla de inventario (`InventoryPanel` en HUD + `hud.gd`): abre con I/Tab
      (pausa), lista equipo + bolsa, clic para equipar (swap, viejo→bolsa), comparación ▲/▼ por
      item_score. `Player.equip_from_bag`, `Items.describe`. Verificado por eval.
      F7c HECHO: barras visuales de vida/maná/XP (ColorRects), menú de pausa (Esc), pantalla de
      muerte con stats + reiniciar (reload_current_scene + reset_run). Verificado por eval.
      PENDIENTE (opcional, más adelante): tienda del mercader (necesita entidad mercader en la
      mazmorra), menú/pantalla de inicio.
- [~] F8 — Contenido/assets. F8a-1 HECHO (2026-06-14): copiados 198 PNGs del héroe a
      `res://assets/hero/` (mage idle/walk/hurt/walk_empty/idle_holdpose_ref/power/powerboom +
      staffs 1-9 + staff9_anim + hands). Generado `assets/hero/mage_frames.tres` (SpriteFrames
      con 30 animaciones, autocontenido, ImageTextures embebidos) vía game_eval con
      Image.load_from_file + ResourceSaver.save. Estructura `/Main/Player/Rig/{Body,Hand/{Weapon/Tip,HandOverlay}}`
      + AnimationPlayer. Body = AnimatedSprite2D con filter Nearest, scale 0.4, autoplay idle_south.
      `player.gd` actualizado: 8 octantes por velocity.angle, switch idle↔walk según move.
      Verificado por eval (8 dirs cambian correcto).
      F8a-2 HECHO (2026-06-14): `assets/hero/mage_anims.tres` (AnimationLibrary, 10 anims:
      idle/walk × 5 dirs base) con tracks `Body:animation` + `Body:frame` + `Hand:position`
      (vacío). AnimationPlayer asignado en main.tscn. `Data.STAFF_RIG` (tabla portada del
      v2hero.js, 9 staffs: grip/focus/rot). Player carga staffs+hands en runtime
      (Image.load_from_file porque no están importados), Weapon Sprite2D con offset=-grip
      y rotation por staff. `Tip.position = focus - grip` → proyectil sale de Tip.global_position.
      HandOverlay con texturas south/SE/E. Z-order: Weapon z=-1 al norte. Mirror para W/SW/NW
      vía Rig.scale.x = -0.4.
      F8a-3 HECHO (2026-06-14): Felipe marcó los anchors del Hand frame por frame en el
      AnimationPlayer con auto-keyframe. Total keys: walk_south=9, walk_south_east=6,
      walk_east=4, walk_north_east=4, walk_north=3, idle_south_east/east/north_east/north=1,
      idle_south=0 (sigue funcional por herencia de la anim anterior; agregar 1 key cuando
      quiera para robustez). Visualmente perfecto en las 5 dirs base + mirror W/SW/NW.
      Proyectil sale de Tip.global_position (offset +7.7,-21 en east).
      F8a COMPLETO + PULIDO (2026-06-14): fix diagonales swappeadas en idle_holdpose
      (NE↔NW, SE↔SW); escala de varas spx/ancho (staff5-8 128px→0.5); overlay de pulgar
      NE (hands/north-east.png); vara visible al N/NE/NW; walk lateral con brazo estático
      (StaffArm desde idle east) + grip fijo + z vara1<brazo2<cuerpo3; quitado overlay east.
      PENDIENTE F8b: mobs sheet (slime/lich/ghost/zombie/orc). F8c: mobs frame
      (rata/skeleton). F8d: tilesets reales. F8e: jefe rugby + items visuales. F8f: audio.  ← próximo
- [ ] F9 — Luz & polish (Light2D, glow, partículas, screen-shake)
- [ ] F10 — Persistencia (guardar run en user://), récords, pisos persistentes
- Pendiente menor: no spawnear enemigos a X tiles del spawn; pattern kickball del jefe; arena de jefe + encuentro al cerrar zona; quitar flags DEBUG_BOSS.
- Polish opcional pendiente: no spawnear enemigos a X tiles del punto de aparición.
