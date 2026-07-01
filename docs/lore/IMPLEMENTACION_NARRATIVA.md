# Implementación narrativa — hoja de ruta técnica

> **Qué es esto:** el puente entre la biblia (`docs/PLAN_NARRATIVO.md`, `docs/lore/PROPUESTAS_LORE_2026-06-26.md`) y el motor real. Responde *cómo* metemos la narrativa en el juego, por fases, atado a la arquitectura que YA existe en `master`.
> **Estado de partida:** HOY el juego no tiene NADA de texto narrativo (ni intro, ni banner de zona, ni línea de jefe, ni lore de ítem). Todo lo de abajo es por construir.
> **No es:** la biblia (eso vive en los otros dos docs) ni código. Es el plan de ataque.

Refs cruzados: orden de prioridad de entrega → `PLAN_NARRATIVO.md:44-54`; orden de fases → `PLAN_NARRATIVO.md:278-307`; textos paste-ready de documentos → `PROPUESTAS_LORE_2026-06-26.md:71-154`; líneas de jefe/voz/prólogo/falso final → `PROPUESTAS_LORE_2026-06-26.md:158-213`.

---

## 1. Propósito y principios

1. **Data-driven, no hardcodeado.** El texto narrativo vive separado del código, en UN recurso de datos (autoload `Lore` o `.tres`/JSON), igual que `Data.ZONES`/`Data.STAFF_NAMES` viven en `scripts/autoload/data.gd`. Ningún string de lore se escribe inline dentro de `boss.gd`/`main.gd`/`hud.gd`: esos archivos solo *piden* texto por id/trigger.
2. **Cada pieza cuelga de un sistema que ya existe.** No inventamos flujo nuevo donde hay uno: el banner usa el cambio de piso que ya emite `GameState.floor_changed` (`game_state.gd:26`), las líneas de jefe usan las señales/fases que ya tiene `boss.gd`, el lore de ítem usa el `tooltip_text` que ya arma `inventory_panel.gd:363`.
3. **Respetar el orden de prioridad de entrega** (`PLAN_NARRATIVO.md:44-54`): 1º situaciones jugables, 2º narración ambiental, 3º documentos/libros, 4º frases breves de encuentro/jefe, 5º conversaciones. Pero el orden *técnico de construcción* arranca por lo barato y de alto impacto (banners, voz, líneas de jefe, lore de ítem) porque desbloquea "sentir mundo" sin tocar sistemas sensibles — ver Fase 1.
4. **Integración limpia, no reescrituras.** Hay otro agente tocando el repo y Felipe va a probar el refactor reciente (`dungeon.gd` partido en `DungeonGen`/`DungeonDecor`/`DungeonFog`, `CombatDirector` autoload, `ShopPanel`/`InventoryPanel`). Toda pieza narrativa entra por **señal nueva**, **autoload nuevo** o **prop nuevo** — nunca cambiando la firma de algo de lo que dependen otros archivos. Preservar la regla de `AGENTS.md`: "mové la lógica preservando la API pública".
5. **Regla de oro de tono** (`PROPUESTAS_LORE_2026-06-26.md:251-252`): humor en la superficie/sistemas, gravedad en la voz y la consecuencia. Nada de subsuelo/pisos negativos antes del falso final. El plan no fija texto definitivo: usa los borradores de la biblia y respeta las 6 decisiones pendientes (`PROPUESTAS_LORE_2026-06-26.md:215-226`).

---

## 2. Vehículos de entrega

Esfuerzo: **S** ≤ medio día · **M** 1-2 días · **L** 3+ días. Riesgo = probabilidad de romper el refactor reciente.

### 2.1 Banner de nombre de zona — **quick win estrella** · S · impacto ALTO · riesgo NULO
- **Qué es:** al entrar a un piso, un cartel breve con el `name` de la zona (p.ej. "Torre en Ruinas") + subtítulo de capítulo, que aparece y se desvanece (estilo Hades/Diablo).
- **El gancho ya existe:** `Data.ZONES` tiene `name` por zona (`data.gd:54-56`: "Torre en Ruinas", "Cavernas Hondas", "Santuario Profano") y **HOY no se muestra en ningún lado**. `main._build_floor()` ya lee `zone` (`main.gd:126`) y `next_floor()` ya emite `GameState.floor_changed` (`main.gd:153`).
- **Archivos:** `scripts/hud.gd` (nuevo método `_on_floor_changed` que escucha `GameState.floor_changed`, lee `Data.ZONES[run.zone_idx].name` y anima un `Label` propio en el CanvasLayer del HUD). Cero cambios en `main.gd` salvo, opcional, disparar también el banner en el primer piso desde `_ready` (hoy `floor_changed` solo se emite al *avanzar*, no al cargar el piso 1 — ver nota abajo).
- **Nota de integración:** el primer piso de la run NO emite `floor_changed` (`main.gd` llama `_build_floor()` directo en `_ready`). Para que el banner salga también al arrancar, agregar una llamada explícita en `hud.gd` cuando `GameState.mode` pasa a `PLAY` (ya escuchado en `hud._on_mode`, `hud.gd:241`) o emitir `floor_changed` una vez al final de `main._ready`. Preferible lo segundo: 1 línea, mantiene al HUD como puro consumidor.
- **Plus barato:** aplicar el renombre `cavernas` → "Entrañas de la Torre" (decisión de la biblia, `PROPUESTAS_LORE_2026-06-26.md:48,65`) es editar UN string en `data.gd:55`. Hacerlo junto con el banner: el banner lo vuelve visible y le da sentido.

### 2.2 Voz del Archimago (floaters/línea breve en hitos) · S-M · impacto ALTO · riesgo BAJO
- **Qué es:** líneas cortas en primera persona del protagonista en hitos: entrar a una zona nueva, ver el primer enemigo transformado, pararse al borde de la escalera/salida. Muestras en `PROPUESTAS_LORE_2026-06-26.md:189-196`.
- **Vehículo más barato (reusar lo que hay):** `GameState.floater(pos, text, color)` ya existe (`game_state.gd:46-52`) y ya se usa para avisos de mundo (ej. "Un mercader apareció…", `main.gd:228`). Una línea de voz = un floater anclado al jugador, con color cálido tenue. Cero infraestructura nueva para el MVP.
- **Vehículo "nice" (Fase 4):** una caja de subtítulo inferior persistente (Label en CanvasLayer del HUD) que dura ~3s, para frases más largas que un floater. Es la "caja mínima para frases breves, sin retratos" de `PLAN_NARRATIVO.md:288`.
- **Triggers y dónde colgarlos:**
  - *Entrar a zona nueva:* mismo hook del banner (`floor_changed` → cuando `floor_in_zone == 0`). En `hud.gd` o en un autoload `Lore` que escuche la señal.
  - *Primer enemigo transformado del piso:* `GameState.enemy_killed`/spawn — más simple: un flag `run["voice_seen"]` para no repetir, chequeado en `enemy.gd` al primer aggro, o disparado desde `main._spawn_enemies`. Mantenerlo en el autoload `Lore` para no ensuciar `enemy.gd` (sensible).
  - *Borde de escalera/salida:* el `_exit` Area2D de `main.gd:165-202` ya detecta al player con `body_entered` (`main.gd:199`). Agregar un segundo Area2D "umbral" más grande, o reusar el `body_entered` del exit para soltar una línea la primera vez (flag en `run`).
- **Anti-spam:** todo trigger de voz consulta y marca un set de flags `run["lore_flags"]` (persistido, ver §3) para no repetir. Sin esto, la voz cansa.

### 2.3 Líneas de jefe pre/durante/post · S-M · impacto ALTO · riesgo BAJO
- **Qué es:** frase al aparecer, frase(s) durante el combate (al enrage), frase al morir. Textos en `PROPUESTAS_LORE_2026-06-26.md:170-187` (Bucle/Rennod, Gólem Anciano, El Liche).
- **Los hooks ya existen en `boss.gd`:**
  - **PRE:** `setup_boss()` ya emite `GameState.boss_spawned.emit(self)` (`boss.gd:56`). El HUD ya lo escucha para la barra (`hud._on_boss_spawn`, `hud.gd:197`). Soltar la línea PRE ahí (floater sobre el jefe o caja de subtítulo).
  - **DURANTE (enrage):** `take_damage()` ya detecta el cruce del 50% y setea `enraged = true` UNA vez (`boss.gd:255-257`). Es el punto natural para la línea "durante": agregar ahí `Lore.boss_line(boss_key, "mid")`.
  - **POST:** `_die()` ya emite `GameState.boss_died.emit()` (`boss.gd:264`). Soltar la línea POST antes del `queue_free()`, o desde quien escuche `boss_died` (hoy lo escuchan `main._on_boss_died` y `hud._on_boss_died`).
- **Texto data-driven:** las líneas se piden por `boss_key` (ya disponible: `boss.gd:13`, valores "bucle"/"golem_anciano"/"liche") a la tabla de `Lore`. `boss.gd` NO contiene los strings.
- **Riesgo:** bajo; son 3 llamadas en puntos que ya disparan eventos. No tocar la máquina de patrones.

### 2.4 Lore de ítem en el tooltip del inventario · S · impacto MEDIO-ALTO · riesgo NULO
- **Qué es:** sumar una línea de "sabor" al tooltip de un ítem (sobre todo varas), debajo de los stats. Aprovecha que `STAFF_NAMES` (`data.gd:144-151`) ya son nombres con peso de lore ("Vara de Aelyr", "Cetro de Noctharion"…).
- **El gancho ya existe:** el tooltip se arma en DOS lugares y ambos ya concatenan nombre + rareza + `Items.describe(it)`:
  - bolsa: `inventory_panel.gd:363` (`btn.tooltip_text = "%s [%s]\n%s"`).
  - paper-doll: `inventory_panel.gd:399` (mismo patrón).
  - tienda: nombre coloreado en `shop_panel.gd:98-101` (se le puede sumar tooltip igual).
- **Cómo:** una función `Items.flavor(it)` (o `Lore.item_flavor(it)`) que devuelve un epíteto según `weapon_type` + tier de material + rareza, y se concatena al `tooltip_text`. Tabla de epítetos data-driven (un dict por tier/rareza). El lugar más limpio es `items.gd` (que ya tiene `describe()` en `items.gd:78-87` y `_staff_name()` en `items.gd:125-127`), o el autoload `Lore` si querés todo el texto narrativo en un solo archivo. **Recomendado:** `Lore.item_flavor()` para no dispersar texto.
- **Esfuerzo mínimo:** una tabla de ~6 epítetos por tier de vara + concatenar en los 2 tooltips. Sin tocar la generación de ítems.

### 2.5 Sistema de documentos/coleccionables + lector con scroll + registro en save · M-L · impacto ALTO · riesgo BAJO
Es el "Fase 1 — base técnica" de la biblia (`PLAN_NARRATIVO.md:280-288`). Tres partes:

**(a) Prop "documento" (se levanta como un ítem).**
- **Patrón a copiar:** `Chest`/`Merchant` son el molde exacto. Un `Document extends Area2D` con: `add_to_group("interactable")` (lo consulta el AoE de E del player, ver `chest.gd:15` y `merchant.gd:12`), `collision_mask = 2`, prompt "[E] Leer", `body_entered`/`body_exited` para `_near`, e `interactable_now()` (`chest.gd:85`, `merchant.gd:65`). Al apretar E → pide al HUD abrir el lector con el id del documento, y marca el doc como hallado en `run["docs_found"]`.
- **Limpieza al regenerar piso:** `main._build_floor()` borra por tipo/grupo (`main.gd:107`). Agregar `Document` (o un grupo `"document"`) a esa lista para que se limpie igual que cofres/puertas.
- **Spawn:** en `main.gd`, función `_spawn_documents()` análoga a `_spawn_chests()` (`main.gd:250-272`). Colocación por **rol de sala** (ya disponible: `dungeon.room_roles`, leído vía `main._room_role()`, `main.gd:231`): p.ej. documentos en `treasure`/`combat`, nunca en `entry`/`boss`. Gating de visibilidad con `_gate(node, false)` (`main.gd:243-247`) igual que los cofres.

**(b) Pantalla de lectura con scroll (libros largos).**
- **Patrón a copiar:** `ShopPanel`/`InventoryPanel` (Control full-rect, `process_mode = ALWAYS`, `get_tree().paused = true` al abrir, dim de fondo que bloquea clicks). Ver `shop_panel.gd:12-37` e `inventory_panel.gd:40-49,302-309`.
- **Cómo:** un `ReaderPanel extends Control` instanciado como hijo del HUD (igual que `_shop`/`_inv` en `hud.gd:78-83`). Contenido: `ScrollContainer` + `RichTextLabel` (BBCode para títulos/cursivas de los fragmentos) con el texto largo. Cierra con [E]/ESC. El HUD expone `open_reader(doc_id)` y lo gatea contra el inventario abierto (mismo arbitraje que hoy hace `hud._process` entre inventario y pausa, `hud.gd:186-194`).
- **Texto:** viene del autoload `Lore` por id. Los textos paste-ready ya están: fragmentos cortos `PROPUESTAS_LORE_2026-06-26.md:75-135` y el libro largo "El Archivo que se Reescribe" `PROPUESTAS_LORE_2026-06-26.md:138-154`.

**(c) Registro en el save.**
- **El save ya soporta esto sin tocar el schema:** `SaveSystem.save_run()` serializa `GameState.run` entero como JSON (`save_system.gd:13-17`). Si guardamos los docs hallados dentro de `run` (p.ej. `run["docs_found"] = ["colnir_a", ...]`), persisten gratis con el autosave que ya corre cada 8s (`main.gd:95-97`) y en cada checkpoint de piso (`main.gd:155`). **No tocar `save_system.gd` ni `SCHEMA_VERSION`.**
- **Reset:** `GameState.reset_run()` (`game_state.gd:95-103`) arma el dict inicial; sumar ahí `"docs_found": []` y `"lore_flags": {}` para que arranquen limpios en run nueva.

### 2.6 Pistas ambientales (props/salas con texto mínimo) · M · impacto ALTO (es la prioridad #2 de la biblia) · riesgo MEDIO
- **Qué es:** cadáveres en su puesto, salas selladas, símbolos — con una línea de voz del Archimago al acercarse (`PROPUESTAS_LORE_2026-06-26.md:191-196`: "No huyó. Cumplió la orden hasta que la orden lo mató."). Es narración ambiental, no diálogo.
- **Dos caminos, de menor a mayor riesgo:**
  - **Visual barato (preferido para empezar):** reusar el sistema de decoración que ya existe. `main._spawn_decor()` (`main.gd:334-368`) ya coloca props por sala con `DECOR`/`AtlasTexture` y los gatea. Sumar entradas de decor "narrativas" (cadáver, sello, símbolo) con un trigger opcional: si el prop tiene un `lore_id`, al pisar su celda (o un Area2D chico encima) suelta una línea de voz una vez (flag en `run["lore_flags"]`).
  - **Sala sellada como situación (Fase 2+, más ambicioso):** aprovechar `room_roles` y el modo `USE_DOORS` (puertas = portales, `door.gd`, specs en `dungeon_gen.get_door_specs()` `dungeon_gen.gd:195-211`). Una "sala sellada" = sala sin puerta de entrada normal + un documento dentro. Esto roza procgen (sensible): hacerlo data-driven vía un rol nuevo (`"sealed"`) en `DungeonGen.assign_roles()` (`dungeon_gen.gd:238-283`) y consumirlo en `main.gd`, sin tocar el tallado de salas.
- **Riesgo medio** solo si se mete mano en `dungeon_gen.gd`/`dungeon_decor.gd` durante el refactor. Mitigación: empezar por la rama "visual barato" (solo `main.gd` + prop), dejar los roles de sala nuevos para cuando el refactor esté probado.

### 2.7 Líneas del mercader · S · impacto MEDIO · riesgo NULO
- **Qué es:** una frase de sabor al abrir la tienda y/o al aparecer el mercader post-jefe. El mercader es, en el lore, un personaje (candidato a futuras líneas de Fernir/superviviente).
- **Hooks existentes:** la tienda se abre vía `GameState.shop_requested` → `hud.open_shop()` → `ShopPanel.open()` (`merchant.gd:71`, `hud.gd:69,271`, `shop_panel.gd:28`). El título "MERCADER" se arma en `shop_panel.gd:64`. Sumar ahí una línea bajo el título, pedida a `Lore`. Al *aparecer* el mercader post-jefe, `main._spawn_merchant()` ya tira un floater (`main.gd:228`): se puede variar ese texto por `Lore`.
- **Cero riesgo:** es texto en un panel construido por código.

### 2.8 Prólogo (4 planos) y falso final (Piso 0 → −1) · L · impacto MUY ALTO · riesgo BAJO-MEDIO
**Prólogo** (`PLAN_NARRATIVO.md:64-83`, beats en `PROPUESTAS_LORE_2026-06-26.md:160-168`):
- **Assets listos:** `assets/story/intro_council.png` y `assets/bg/eclipse_vista.png` (verificados en disco; este último ya se usa como fondo en `main.gd:34`).
- **Vehículo:** una escena propia `scenes/prologue.tscn` (4 planos = `TextureRect` + `Label` con fade entre planos por `Tween`, patrón ya usado en `menu.gd:86-88`). Cierra dando control → `change_scene_to_file("res://scenes/main.tscn")`.
- **Punto de entrada:** se dispara desde el menú en "NUEVA RUN". Hoy `menu._on_new()` va directo a `main.tscn` (`menu.gd:242-245`). Cambiar ese destino a `prologue.tscn` (1 línea), y que el prólogo siga a `main.tscn`. "Continuar" (`menu._on_continue`, `menu.gd:248`) NO pasa por el prólogo.
- **Skippeable:** click/ESC salta al juego (no frustrar en re-runs aunque solo salga en run nueva).

**Falso final** (`PLAN_NARRATIVO.md:192-211`, beats en `PROPUESTAS_LORE_2026-06-26.md:204-213`):
- **Dónde se decide hoy la victoria:** `main.next_floor()` detecta que se pasó la última zona y llama `_win()` (`main.gd:150-160`), que setea `Mode.WIN` y limpia el save. El HUD muestra "¡GANASTE!" en `hud._on_mode` (`hud.gd:244-245`).
- **Reemplazo:** en vez de saltar directo a WIN al terminar la zona 3, insertar la secuencia scriptada del Piso 0 (sala iluminada → cartel "PISO 0 — EL FONDO DE LA TORRE" → salida sellada → mecanismo reacciona al registro del Liche → se abre hacia abajo → "−1" → cliffhanger). Puede ser otra escena (`scenes/false_ending.tscn`) o un estado especial dentro de `main`. **Recomendado:** escena propia disparada desde `_win()` (mantiene `main` limpio), que al terminar corta a negro con las últimas líneas (`PROPUESTAS_LORE_2026-06-26.md:213`).
- **Condición del mecanismo:** "reacciona al registro recuperado del Liche" → chequear `run["docs_found"]` por el doc del Liche (depende de §2.5). Si todavía no está el sistema de docs, versión MVP: el mecanismo reacciona incondicionalmente (el giro funciona igual), y se condiciona después.
- **Riesgo:** bajo-medio. Tocar `_win()` es puntual, pero es flujo de fin de run: probarlo sin romper el record/clear_run (`main.gd:158-159`).

---

## 3. Modelo de datos sugerido (forma, sin código)

Un único autoload **`Lore`** (`scripts/autoload/lore.gd`, registrado en `project.godot [autoload]` junto a los demás, `project.godot:23-33`) que centraliza TODO el texto y la lógica de "pedir texto". Alternativa equivalente: un `.tres`/JSON cargado por ese autoload si Felipe prefiere editar datos fuera del `.gd` (igual que `data.gd` podría externalizarse). Empezar con `const` dentro del autoload (como `data.gd` hace con `ZONES`/`STAFF_NAMES`) es lo más simple y consistente con el repo.

**Una entrada de documento/pieza** (boceto de forma):
```
{
  "id": "colnir_a",                  # único, es lo que se persiste en run["docs_found"]
  "registro": "colnir",              # uno de los 7 tipos (ver abajo)
  "kind": "doc_short",               # doc_short | book_long | voice | boss_line | banner | item_flavor
  "zone": "torre",                   # zona/capítulo donde aparece (matchea Data.ZONES[].id)
  "trigger": "pickup",               # pickup | enter_zone | boss_pre/mid/post | first_transformed | exit_edge | shop
  "title": "De la Crónica de los Seis, tomo IX",
  "short": "…",                      # texto breve (floater / doc menor)
  "long": "[BBCode]…",               # texto largo para el ReaderPanel (vacío si no aplica)
  "flags_set": ["read_colnir_a"]     # qué marca al verse/leerse (para variantes y anti-repetición)
}
```

**Los 7 registros** (de `PLAN_NARRATIVO.md:251-258`): `colnir` (crónicas que se contradicen), `durnir` (órdenes de cuarentena), `kilnir` (contratos/censura), `jernir` (planos), `fernir` (notas clínicas), `skarun` (fragmentos tardíos), `voice` (voz del Archimago, no es un clan pero comparte estructura). Los textos ya existen: §B de `PROPUESTAS_LORE_2026-06-26.md:71-154`.

**API pública del autoload (lo que piden los otros archivos):**
- `Lore.boss_line(boss_key, phase)` → string (phase = "pre"/"mid"/"post"). La pide `boss.gd`.
- `Lore.zone_banner(zone_id)` → {name, subtitle}. La pide `hud.gd`.
- `Lore.voice(trigger, ctx)` → string o "" si ya se vio (consulta flags). La piden los triggers de voz.
- `Lore.item_flavor(item)` → string. La piden los tooltips de `inventory_panel.gd`/`shop_panel.gd`.
- `Lore.document(id)` → entrada completa. La pide el `ReaderPanel`.
- `Lore.mark(flag)` / `Lore.has(flag)` → escriben/leen `GameState.run["lore_flags"]` (persisten solos vía el save existente).

**Persistencia (sin tocar el schema):** dos claves nuevas dentro de `GameState.run` (inicializadas en `reset_run()`, `game_state.gd:95-103`):
- `run["docs_found"]: Array[String]` — ids de documentos hallados (para el códice y variantes).
- `run["lore_flags"]: Dictionary` — flags de líneas ya vistas (anti-repetición) y estado de eventos.
Ambas viajan gratis en `SaveSystem.save_run()` (serializa `run` entero, `save_system.gd:17`). No cambia `SCHEMA_VERSION`.

---

## 4. Mapa pieza → archivo → hook

| Elemento narrativo | Archivo/escena que lo implementa | Señal / hook de integración existente |
|---|---|---|
| Autoload de texto `Lore` | `scripts/autoload/lore.gd` (nuevo) + `project.godot [autoload]` (`project.godot:23-33`) | — (lo consultan todos) |
| Banner de zona | `scripts/hud.gd` (Label propio) | `GameState.floor_changed` (`game_state.gd:26`, emitido `main.gd:153`); `name` en `data.gd:54-56` |
| Voz del Archimago (hitos) | `scripts/autoload/lore.gd` + `GameState.floater` (`game_state.gd:46`) | `floor_changed`; `_exit.body_entered` (`main.gd:199`); flags en `run` |
| Línea de jefe PRE | `scripts/boss.gd` | `GameState.boss_spawned` (`boss.gd:56`) |
| Línea de jefe DURANTE | `scripts/boss.gd` | cruce de enrage en `take_damage` (`boss.gd:255-257`) |
| Línea de jefe POST | `scripts/boss.gd` | `GameState.boss_died` (`boss.gd:264`) |
| Lore de ítem (tooltip) | `scripts/ui/inventory_panel.gd` + `scripts/ui/shop_panel.gd` | `tooltip_text` (`inventory_panel.gd:363,399`); `STAFF_NAMES` (`data.gd:144`) |
| Prop documento | `scripts/document.gd` (nuevo, molde `chest.gd`/`merchant.gd`) | grupo `"interactable"` + `interactable_now()` (`chest.gd:85`); limpieza en `main.gd:107` |
| Spawn de documentos | `scripts/main.gd` (`_spawn_documents`, molde `_spawn_chests` `main.gd:250`) | `dungeon.room_roles` vía `_room_role()` (`main.gd:231`); `_gate()` (`main.gd:243`) |
| Pantalla de lectura | `scripts/ui/reader_panel.gd` (nuevo, molde `shop_panel.gd`) | HUD lo instancia como hijo (`hud.gd:78-83`); pausa (`shop_panel.gd:36`) |
| Pistas ambientales (visual) | `scripts/main.gd` (`_spawn_decor`, `main.gd:334`) + `Lore.voice` | gating `_gate()`; Area2D chico o pisar celda |
| Pistas ambientales (sala sellada) | `scripts/dungeon_gen.gd` (rol `"sealed"`, `assign_roles` `dungeon_gen.gd:238`) + `main.gd` | `room_roles` |
| Líneas del mercader | `scripts/ui/shop_panel.gd` (`shop_panel.gd:64`) + `main.gd:228` | `shop_requested` (`merchant.gd:71`) |
| Prólogo (4 planos) | `scenes/prologue.tscn` + script (molde fade `menu.gd:86`) | destino de `menu._on_new` (`menu.gd:245`); assets `intro_council.png`, `eclipse_vista.png` |
| Falso final Piso 0→−1 | `scenes/false_ending.tscn` + script | disparado desde `main._win()` (`main.gd:157`); condición `run["docs_found"]` |
| Registro de docs/flags | `GameState.run` (`game_state.gd:95-103`) | `SaveSystem.save_run` serializa `run` (`save_system.gd:17`) — sin tocar schema |

---

## 5. Plan por fases

Alineado con "Orden recomendado" de la biblia (`PLAN_NARRATIVO.md:278-307`). Cada fase entra sin romper el refactor (señales/autoload/props nuevos).

### Fase 1 — Base técnica (lo barato y de alto impacto primero)
Da "mundo" inmediato tocando solo consumidores de señales que ya existen.
- **Entregables:**
  1. Autoload `Lore` con tablas de banners, voz, líneas de jefe y epítetos de ítem (datos paste-ready ya escritos en la biblia).
  2. Banner de zona (§2.1) + renombre `cavernas`→"Entrañas de la Torre".
  3. Voz del Archimago en 3 hitos vía `GameState.floater` (§2.2), con anti-repetición por `run["lore_flags"]`.
  4. Líneas de jefe PRE/DURANTE/POST (§2.3).
  5. Lore de ítem en los 2 tooltips (§2.4).
- **Criterio de "listo":** al jugar, cada piso muestra el nombre de su zona; los 3 jefes hablan al aparecer, al enrage y al morir; los tooltips de varas tienen sabor; ninguna línea se repite en el mismo piso; compile-check headless OK (`godot --headless --path . --import`, exit 0, sin SCRIPT/Parse Error) — la validación que pide `AGENTS.md`.

### Fase 2 — Esqueleto narrativo
Construye la infraestructura de texto largo y los dos momentos cinemáticos.
- **Entregables:**
  1. Sistema de documentos completo (§2.5): prop `Document`, `_spawn_documents` por rol de sala, `ReaderPanel` con scroll, persistencia en `run["docs_found"]`.
  2. Prólogo (4 planos) enganchado a "NUEVA RUN" (§2.8).
  3. Falso final Piso 0→−1 disparado desde `_win()` (§2.8), MVP con mecanismo incondicional.
  4. Un encuentro jugable distintivo sembrado por zona (esqueleto): empezar por la rama "visual barato" de pistas ambientales (§2.6).
- **Criterio de "listo":** se pueden levantar y leer documentos; el registro persiste al cerrar y continuar; "NUEVA RUN" abre el prólogo y "Continuar" no; terminar la zona 3 lleva al Piso 0 y revela el −1 con las líneas canon; compile-check OK.

### Fase 3 — Personajes
- **Entregables:**
  1. Líneas del mercader (§2.7).
  2. Superviviente Fernir SOLO si el encuentro mejora el juego (`PLAN_NARRATIVO.md:298`): reusar el prop interactivo del mercader/documento para un NPC que suelta 2-3 líneas sobre el escenario, sin retrato. Colnir/Kilnir quedan como autores de documentos, no NPC (`PLAN_NARRATIVO.md:300`).
- **Criterio de "listo":** el mercader tiene voz; si se hace Fernir, es un encuentro breve que devuelve el control rápido (regla `PLAN_NARRATIVO.md:61`).

### Fase 4 — Profundidad
- **Entregables:**
  1. Libros principales largos (el "Archivo que se Reescribe", `PROPUESTAS_LORE_2026-06-26.md:138-154`) en el `ReaderPanel`.
  2. Variantes de texto según `run["docs_found"]` (p.ej. una línea de voz cambia si ya leíste el contrato Kilnir).
  3. Caja de subtítulo inferior para frases más largas que un floater (§2.2).
  4. Opcional: códice/diario accesible desde pausa que liste documentos hallados (lee `run["docs_found"]`).
  5. Sala sellada como rol de procgen (§2.6, rama ambiciosa) — solo con el refactor de dungeon ya probado.
- **Criterio de "listo":** los libros largos se leen completos en una pausa; hay al menos una variante condicionada por documento; el códice refleja lo hallado.

---

## 6. Quick wins de los primeros 1-2 días

Máximo mundo, mínimo código, cero riesgo para el refactor (no tocan `dungeon*`, `enemy.gd`, procgen ni el save schema):

1. **Banner de nombre de zona** (§2.1) — el `name` ya está en `data.gd:54-56` y no se usa; el HUD ya escucha `floor_changed`. Es el de mayor impacto/costo. **Encabeza.**
2. **Lore de ítem en el tooltip** (§2.4) — concatenar un epíteto en `inventory_panel.gd:363,399`. Reusa `STAFF_NAMES`. **Segundo.**
3. **Renombre `cavernas` → "Entrañas de la Torre"** (`data.gd:55`) — 1 string; el banner lo vuelve visible. Va pegado al #1.
4. **Líneas de jefe PRE/POST** (§2.3) — 2 llamadas en hooks que ya disparan (`boss.gd:56` y `boss.gd:264`). Texto ya escrito en la biblia.
5. **Línea del mercader al abrir la tienda** (§2.7) — 1 Label bajo el título en `shop_panel.gd:64`.

Los 5 viven en un solo autoload `Lore` nuevo + ediciones puntuales en consumidores. Ninguno cambia una firma de la que dependa otro archivo, así que conviven con el otro agente y con la prueba del refactor.

---

### Notas de seguridad para no romper el refactor reciente
- **No** cambiar firmas/estado público de `dungeon.gd` ni de sus módulos `DungeonGen`/`DungeonDecor`/`DungeonFog` (otros archivos dependen de `dungeon.*`; regla de `AGENTS.md`). Cualquier rol de sala nuevo se *agrega* en `assign_roles` (`dungeon_gen.gd:238`) y se consume en `main.gd`, sin tocar el tallado iso.
- **No** tocar `save_system.gd` ni `SCHEMA_VERSION` (`save_system.gd:8`): el lore persiste como claves nuevas dentro de `run`.
- **No** ensuciar `boss.gd`/`enemy.gd`/`main.gd` con strings: piden texto a `Lore`. Mantener `hud.gd` como consumidor de señales (no meterle lógica de mundo).
- Validar cada fase con compile-check headless; **no** abrir el juego ni screenshotear salvo que Felipe lo pida (`AGENTS.md`).
