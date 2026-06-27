> ⚠ **AVISO DE OBSOLESCENCIA:** este es un **PLAN / doc histórico** (snapshot de diseño 2026-06-26) y **puede divergir del código actual** sin que se avise aquí. Las notas inline (p. ej. la "CORRECCIÓN/auditoría") son parches sobre el plan, no garantía de paridad.
> La **fuente viva** del comportamiento real es: **AGENTS.md** + **docs/architecture_notes_2026-06-26.md** + el **código** (`dungeon.gd`, `enemy.gd`, `scripts/visibility_manager.gd`, `light_cfg.gd`). Ante cualquier duda, mandá el código.

# Oscuridad & Visibilidad — Plan (estilo Diablo 2)

> Estado: **Fase 1 IMPLEMENTADA** (2026-06-26) — falta la validación visual de Felipe (caso A→B). Reemplazó al overlay `room_darkness` por-sala.
>
> **Implementado:**
> - Overlay `room_darkness.gd` eliminado (a Papelera) + hooks retirados de `dungeon.gd`.
> - **Luz oscura:** `user://light_knobs.json` + DEFS de `light_cfg.gd` → `amb` 0.08/0.08/0.11, `foot_ambient` 0.28 (era 1.0 = causa raíz), `player_energy` 2.0, `exposure` 1.0. **Tuneable en vivo: tecla L** (persiste al JSON). Para revertir mi tuning: panel L o `LightCfg.reset()`.
> - **Grilla de visibilidad** en `dungeon.gd`: `cell_seen` (sticky) + `_visible_now` (radio actual, `VIS_RADIUS=6`); getters `is_cell_seen/is_cell_visible/is_seen_cell/world_to_cell`; update en `_update_iso_wall_mat` cada frame; init por piso.
> - **Minimapa** lee `dungeon.is_seen_cell` (fuente de verdad = Dungeon; `_explored`→`_drawn` cache).
> - **Gating:** `scripts/visibility_manager.gd` (hijo de Main, cada 4 frames, grupo `vis_gated`). Objetos del mundo (cofre/mercader/decor) = sticky al verse. Floater de daño de enemy gateado por visibilidad (anti-spoiler).
>
> ⚠ **CORRECCIÓN (auditoría 2026-06-26):** después se agregó la **luz propia de mobs** y los **mobs salieron del manager**: ahora `enemy.gd` se **auto-gatea por DISTANCIA** (`to_player <= mob_reveal_dist` + `is_cell_seen`), NO por celda/`is_cell_visible`. Por eso la rama `vis_threat` del manager quedó **muerta** y el gating de mobs es un **disco de distancia** (no respeta paredes/LOS — OK en modo puertas porque las salas están lejos). El **boss NO se gatea** (siempre visible). A futuro: unificar la visibilidad de amenazas en un solo lugar (manager) y, si se quiere ocultar tras paredes, sumar line-of-sight/shadowcasting. Ver `code_audit_2026-06-26.md`.
>
> **Validación (Felipe):** parado en A → B oscuro · cara de muro hacia A iluminada · el vano deja entrever B · mobs de B no se ven hasta entrar a tu radio · minimapa revela igual que antes. Si B no se ve suficientemente oscuro: bajar más `foot_ambient`/`exposure` en el panel L. Si el radio (6 tiles) no calza con la luz visual: tunear `player_radius` o `VIS_RADIUS`.

## Filosofía (lección Diablo 2)

D2 separa **tres** sistemas que solemos mezclar:

1. **Luz del mundo** — dinámica, por fuentes de luz (antorcha del player, antorchas de sala, ambient).
   Continua y **por radio**, NO por cuarto. Oscuridad = *ausencia de luz*, no un velo negro encima.
2. **Memoria de mapa** — el automap/minimapa recuerda la geometría explorada. NO da info viva.
3. **Ocultar info** — lo no visto/oscuro esconde enemigos, items y layout (tensión de exploración).

Regla de oro: **"explorado" = recordado (mapa), NO iluminado para siempre.** La luz del mundo es siempre la actual.

## Decisión de arquitectura (clave)

El overlay por-sala que había era **Baldur's Gate 3, no D2**, y peleaba contra el sistema de luz. Además, un velo
fullscreen que oscurece todo rompe el caso "cara de muro hacia A iluminada / interior de B oscuro" por el z-order iso.

**Insight raíz:** este motor YA produce la oscuridad correcta con su luz (PointLight2D del player + `LightField`
foot-lit en muros + occluders + `CanvasModulate`). El problema era que el **ambient estaba muy claro** (~0.32), así
que parecía hacer falta tapar con un velo. → **Bajamos el ambient y dejamos que la luz haga el trabajo.** Sin velo.

Entonces el "fog" se reduce a dos cosas que **NO oscurecen** (y por eso no rompen el z-order):

- **Gating de info:** ocultar entidades en celdas no vistas.
- **Memoria:** el minimapa (capa UI), leyendo la verdad desde `Dungeon`.

`Dungeon` = **fuente de verdad** de exploración (`cell_seen`, `cell_visible`). El minimapa **lee**, no calcula.
(No al revés: el gameplay no debe depender de un sistema de UI.)

## Estado por celda

```
UNSEEN   nunca vista        → entidades ocultas, no en minimapa, mundo negro (por falta de luz)
SEEN     vista alguna vez    → aparece en minimapa; mundo oscuro si no llega luz (no velo de "recuerdo" en Fase 1)
VISIBLE  en radio ahora      → entidades visibles; mundo iluminado por la luz real
```

## Plan por fases

**Fase 1 (esta) — reversible, sin tocar arte:**
1. Sacar el overlay `room_darkness` (los 3 hooks en `dungeon.gd` + el script a Papelera).
2. Oscurecer el mundo con luz: bajar `CanvasModulate` Ambient (~0.10) + ambient del `wall_face`/`LightField` + tunear el `PointLight2D` del player. → **Validar caso A→puerta→B con pura luz.**
3. `Dungeon`: `cell_seen[]` / `cell_visible[]` por radio; getters `is_cell_seen/is_cell_visible(world_pos)`.
4. Minimapa lee esa data (invertir dependencia).
5. Gating de entidades: `visible=false` si su celda no fue vista. Los enemigos **siguen simulando** (acechan en la sombra); solo se gatea el render.

**Validación dura (antes de seguir):** parado en A → B oscuro, cara de muro hacia A iluminada, el vano deja entrever B; los mobs de B no se ven hasta entrar.

**Fase 2 (después, opcional):**
- "Memoria" de explorado: aclarado sutil de celdas vistas-pero-oscuras si navegar de vuelta en negro molesta (knob; D2-puro no lo usa, se guía por el minimapa).
- Aggro de mobs ligado al radio de luz (sigilo real D2).
- Line-of-sight con shadowcasting simétrico (no ver doblando la esquina) si el radio + occluders no alcanza.

## Knobs (a exponer)
- Ambient del mundo (oscuridad base).
- Radio de luz del player (cuánto ves).
- `sight_radius` de la grilla de visibilidad (cuándo se marca seen/visible).
- Política de gating por tipo (ocultar si !seen vs si !visible).

## Modo PUERTAS / salas aisladas (banco de pruebas, 2026-06-26)

Para probar la oscuridad con salas realmente separadas: `Dungeon.USE_DOORS` (true).
- **Salas cerradas:** no se tallan corredores (se mantiene el grafo MST) y se saltea `_remove_thin_walls` (no fusiona vecinas). Cada sala = caja cerrada con sus antorchas.
- **Puertas teleport:** por cada arista del grafo, una puerta-beacon (`door.gd`, glow + luz, siempre visible) en el borde de la sala mirando a la conectada. Al tocarla → SALTÁS al interior del otro cuarto (cooldown 700ms anti-rebote). `dungeon.get_door_specs()` + `main._spawn_doors()`.
- **Reversible:** `USE_DOORS=false` vuelve a los corredores zigzag.
- **Pasillos (anotado):** nunca < 2 tiles de piso de ancho (con muros altos, 1 tile no se ve). Futuro con muros más bajos → 1 tile (comentado en `dungeon._connect`).

## Decisiones abiertas para Felipe
- EXPLORADO en el mundo: **negro total** (D2-puro, te guiás por minimapa) vs **dim suave** (roguelite). Fase 1 = negro total (sin velo). Probar y decidir en Fase 2.
- ¿Mobs se re-ocultan al salir de la sala (cell_visible) o quedan visibles una vez vistos hasta apagarse por la oscuridad? Default propuesto: ocultar solo si !seen; el resto lo apaga la luz.
