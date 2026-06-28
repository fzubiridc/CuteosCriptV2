# De WebGL/Compatibility a Desktop .exe — auditoría gráfica y upgrades

> Auditoría 2026-06-28 tras el cambio de deploy a **ejecutable Desktop (Windows)** el 2026-06-27.
> Objetivo: revisar todo lo que estuvo limitado por WebGL2/Compatibility y ver qué se puede subir de calidad
> ahora que corremos Forward+ nativo. **Este doc NO cambia código del juego**, solo lista hallazgos y recomendaciones.

---

## Resumen ejecutivo

1. **El renderer YA está en Forward+** (`project.godot:15` + `rendering_device/driver.windows="d3d12"` en `project.godot:124`), **y el glow 2D ya está activado** (`scenes/main.tscn:67-69`) y **HDR 2D también** (`project.godot:125`). El cambio #1 más temido ya está hecho. La pregunta real ahora es de *afinado*, no de migración.
2. **El quick win más grande y barato: MSAA 2D**. No hay ninguna línea `rendering/anti_aliasing/...` en `project.godot` → está en **desactivado** (default). En arte iso con muchos bordes diagonales (rombos, fachadas) un MSAA 2D ×2/×4 limpia el "escalerado" sin tocar el pixel-art interno. Era impensable en WebGL por costo; en Desktop es casi gratis.
3. **`shaders/post_fx.gdshader` existe pero NO está cableado** en ninguna escena (búsqueda en `*.tscn` = 0 hits). Es saturación+exposición de pantalla, escrito explícitamente para suplir lo que el WorldEnvironment 2D no daba. En Desktop podés decidir: o lo conectás (un ColorRect full-screen en `FX`) o lo descartás y subís el grado vía glow. Hoy es código muerto.
4. **El modelo de luz custom (LightField CPU + uniforms + `wall_face.gdshader`) NO es un workaround de WebGL** — es una decisión de *look* (foot-light estilo Pixi, caras unshaded). Funciona en Forward+ igual. **No reescribir a PointLight2D nativo** (ver "No tocar"). El cap mágico y el `MAX_LIGHTS=64` no eran límites de WebGL.
5. **Las partículas están mixtas**: las "motes" del player ya son `GPUParticles2D` (`scenes/player.tscn:40`) y los hechizos data-driven usan `GPUParticles2D` (`scripts/fx/spell_fx.gd:47`). **La estela del orbe/bolt sigue en `CPUParticles2D`** (`scripts/projectile.gd:68`) — candidato directo a subir a GPU ahora que no hay WebGL.

---

## Quick wins (seguro y barato)

| Cambio | Archivo / setting | Impacto | Riesgo |
|---|---|---|---|
| Activar **MSAA 2D ×2** (subir a ×4 si rinde) | `project.godot` → `rendering/anti_aliasing/quality/msaa_2d` | Bordes iso (rombos, fachadas, muros diagonales) suaves sin emborronar el pixel-art interno | Muy bajo |
| Subir/afinar **glow 2D** | `scenes/main.tscn:67-69` (`glow_intensity=0.7`, `glow_hdr_threshold=1.2`) | Bloom real en bolts/auras/fuego/lava/AoE — los FX ADD ya emiten por encima de 1.0, el glow los "agarra" gratis | Bajo (es de *look*; tunealo con Felipe) |
| Subir estela del bolt a **GPUParticles2D** | `scripts/projectile.gd:68` | Más partículas/estela sin costo CPU; sub-emitters/turbulencia posibles | Bajo (FX aislado) |
| **Limitar FPS** explícito (`Engine.max_fps`) + decidir vsync | autoload (no existe hoy) | Evita que el .exe corra a 1000fps quemando GPU/calentando laptop en menús | Muy bajo |
| Decidir destino de `post_fx.gdshader` (cablear o borrar) | `shaders/post_fx.gdshader` (orphan) | O ganás grade de pantalla (saturación/exposición) o limpiás código muerto | Bajo |
| Subir **glow levels/bloom** del Environment a calidad alta | `Environment_tipki` en `main.tscn` (faltan `glow_levels/*`, `glow_strength`, `glow_bloom`) | Bloom más suave/ancho; en WebGL el glow 2D ni andaba | Bajo |

---

## 1. Renderer actual

- `project.godot:15` → `config/features=PackedStringArray("4.6", "Forward Plus")`. **Ya es Forward+**, no `gl_compatibility`. No hay `rendering/renderer/rendering_method` explícito sobreescribiéndolo → toma Forward+. ✅
- `project.godot:124` → `rendering_device/driver.windows="d3d12"`. Bien para Windows desktop (Direct3D 12). Para un futuro Mac, Godot usará Metal automáticamente; no hay que tocar nada salvo testear.
- `project.godot:125` → `viewport/hdr_2d=true`. ✅ **HDR 2D activo** — necesario para que el glow capture valores >1.0 (los FX ADD). Esto en Compatibility no existía.
- `project.godot:123` → `textures/canvas_textures/default_texture_filter=0` (Nearest). ✅ Correcto para pixel-art; **no tocar**.
- `display/stretch/mode="canvas_items"` (`project.godot:41`). OK para escalado de UI.
- **Falta (recomendado añadir):**
  - `rendering/anti_aliasing/quality/msaa_2d` → no existe = **desactivado**. **Quick win principal.**
  - `rendering/anti_aliasing/quality/screen_space_aa` (FXAA) → suele emborronar pixel-art, **dejarlo off**; preferir MSAA 2D.
  - No hay `rendering/2d/snap/*` (snap 2D transforms/vertices a píxel). Para un juego pixel-art con cámara que se desliza, evaluar `snap_2d_transforms_to_pixel` con cuidado (puede causar "jitter" con la cámara que sigue al player — testear, no es free).

**Veredicto:** la migración de renderer está hecha y bien. Lo que queda es activar AA y afinar post.

---

## 2. Partículas (CPU vs GPU)

Inventario de cada FX y dónde corre hoy:

| FX | Tipo de nodo | Dónde | CPU/GPU | ¿Subir? |
|---|---|---|---|---|
| Motes ambientales del player | `GPUParticles2D` | `scenes/player.tscn:40` (amount=22, preprocess=5) | **GPU** ✅ | Ya está bien |
| Lluvia/partículas de hechizo (data-driven) | `GPUParticles2D` | `scripts/fx/spell_fx.gd:47`, perfil en `element_profile.gd:28` | **GPU** ✅ | Ya está bien |
| **Estela del orbe / bolt** | `CPUParticles2D` (amount=12) | `scripts/projectile.gd:68` | **CPU** | **Sí → GPU** (quick win). Con muchos proyectiles a la vez, 12 partículas CPU × N orbes suma. En GPU es gratis y podés subir amount/lifetime |
| Llamas de quemado (BurnFx) | Sprites animados ADD (no partículas) | `scripts/burn_fx.gd` | CPU (sprites + tween) | Opcional: GPUParticles2D con sub-emitter daría humo/chispas más ricos. Bajo prioridad, el look actual con pixel-art propio es deliberado |
| Fuego de fogata | Sprite animado (unshaded) | `scripts/campfire.gd` | CPU (animación) | Es arte pixel propio → **no convertir** (rompería el estilo); a lo sumo sumar chispas GPU encima |
| AoE (glifo + explosión) | Sprites/llamas ADD + luz | `scripts/aoe.gd` | CPU | Opcional: chispas/turbulencia GPU al explotar. Bajo prioridad |
| Impacto de bolt vs muro | Disco azul ADD (Sprite2D) | `scripts/projectile.gd:331` | CPU (1 sprite + tween) | Está bien; un GPUParticles burst de chispas sería un plus cosmético |
| Estela del dash | Sprite unshaded | `player.gd` | CPU | OK |

**Recomendación:** el único cambio claro es **`projectile.gd:68` → GPUParticles2D**. El resto de los FX "de fuego" son **arte pixel-art deliberado de Felipe**, no partículas genéricas — convertirlos a GPUParticles rompería el estilo (ver memoria: arte = Felipe, lógica = Claude). Las partículas GPU se reservan para humo/chispas/turbulencia que *complementen* el arte, no que lo reemplacen.

**Cosas que Forward+ habilita ahora y antes no (si las querés):** turbulencia, sub-emitters, attractors y particle collision en `GPUParticles2D`. Útiles para: chispas que reboten en el piso al explotar el AoE, humo que se desvíe, estela del bolt con turbulencia. Todo opcional/cosmético.

---

## 3. Glow / post-proceso

- **Glow YA activo:** `scenes/main.tscn:67-69` → `glow_enabled=true`, `glow_intensity=0.7`, `glow_hdr_threshold=1.2`. ✅ Esto en Compatibility/WebGL **no funcionaba**; ahora sí.
- **HDR 2D activo** (`project.godot:125`) → los materiales **ADD** (`scripts/autoload/fx_materials.gd:16`) pueden superar 1.0 y el glow los captura. El stack ya está montado para bloom real en: orbe glow, fuego del AoE, discos de impacto, auras de mob/boss, bolts.
- **Falta afinar el Environment:** el `Environment_tipki` (`main.tscn:63-69`) solo define intensity/threshold. Podés sumar `glow_levels/*` (qué tan ancho), `glow_strength`, `glow_bloom`, `glow_blend_mode` para controlar el look. Ojo: `glow_hdr_threshold=1.2` está alto — algunos ADX brillantes quizás no lleguen; bajalo a ~1.0 si querés más bloom (probar con Felipe).
- **Interacción cap ↔ glow:** `wall_face.gdshader:20` tiene `cap=1.4` y `LightField` cappea a `LightCfg.LIGHT_CAP`. Las **caras de muro y entidades nunca pasan de ~1.4**, así que el glow las toca poco (es deliberado: las caras son look mate). El bloom real lo dan los **FX ADD unshaded** (que sí pasan de 1.0). Esto está bien diseñado, no hay conflicto.
- **`shaders/post_fx.gdshader` es código muerto:** no aparece en ningún `.tscn`. Su propio comentario (`post_fx.gdshader:3-4`) explica que existe porque "el WorldEnvironment 2D solo aplica glow, tonemap/adjustments no afectan al 2D". En Desktop sigue siendo cierto (el grade de pantalla en 2D hay que hacerlo a mano), así que si querés saturación/exposición global, **cablealo** (un `ColorRect` full-screen en el `FX` CanvasLayer con este material). Si no, **borralo** para no confundir.

**¿Se beneficia algo de glow real que hoy use un workaround?** Los "discos azules aditivos" de impacto vs muro (`projectile.gd:284-336`) y los halos ADD son justamente lo que el glow potencia — **no son workarounds a reemplazar, son la fuente del bloom**. No hay "glow falso" que el bloom deba sustituir; el diseño ya es ADD+HDR+glow.

---

## 4. Luz (el sistema sensible)

**Arquitectura actual (triplicada, a propósito):**
- `scripts/autoload/light_field.gd`:
  - `sample(pos)` (`light_field.gd:138`) — tinte **por-CPU** de entidades foot-lit. Lo llama `player.gd:345` **cada frame** para el rig.
  - `pack_lights()` (`light_field.gd:46`) — empaqueta luces a uniforms **cada frame** (`_process`, `light_field.gd:39`), con buffers pre-alocados (ya optimizado contra GC).
  - `entity_material` — ShaderMaterial compartido por mobs/boss (`enemy.gd:133`), luz por-píxel.
- `shaders/wall_face.gdshader` — el mismo modelo de luz por fragmento para caras de muro **y** entidades. `MAX_LIGHTS=64`.

**¿Era esto un workaround de WebGL?** **No.** Es una decisión de *look*: foot-light estilo Pixi (la luz llega "por los pies", las entidades unshaded no se oscurecen contra una pared), caras de muro unshaded con sombra desde la esquina. PointLight2D nativo de Godot **no reproduce este modelo** (aplicaría sombra/oclusión estándar). El `MAX_LIGHTS=64` y el `LIGHT_CAP` son tuning de diseño, no límites del WebGL.

**¿Forward+ habilita algo mejor?** En teoría PointLight2D + CanvasModulate + normal-maps por sprite. Pero:
- Reemplazaría el look custom foot-lit por iluminación 2D estándar → **cambia la estética que ya está pulida**.
- Es el subsistema marcado como **sensible** en `AGENTS.md` (iluminación/antorchas/visibilidad).
- El costo CPU actual (`sample` 1×/frame para el player + `pack_lights` 1×/frame para ≤64 luces) es **barato** y ya está libre de allocs.

→ **Recomendación: NO migrar el modelo de luz.** Está bien donde está. (Ver "No tocar".)

**Único afinado de bajo riesgo posible:** ahora que hay GPU de sobra, podrías subir `MAX_LIGHTS` de 64 a 128 si alguna vez topás el cap con muchas antorchas+fogatas+auras visibles a la vez (hay que cambiarlo en `light_field.gd:17` **y** `wall_face.gdshader:11` en sincronía). Hoy 64 alcanza; solo si se nota el corte.

---

## 5. Texturas / import

Revisado `assets/hero/staffs/staff1.png.import` (representativo del pixel-art):
- `compress/mode=0` (**Lossless**) — ✅ correcto para pixel-art. **No** es VRAM-comprimido, y está bien: comprimir pixel-art a VRAM (DXT/ETC) introduce artefactos. Esto **no es** una limitación de WebGL que haya que revertir.
- `mipmaps/generate=false` — ✅ correcto para sprites 2D pixel-art (mipmaps emborronarían). No tocar.
- `detect_3d/compress_to=1` — irrelevante en 2D.
- `default_texture_filter=0` (Nearest, `project.godot:123`) — ✅ pixel-art nítido.

**Veredicto:** el import está bien y **no estaba limitado por WebGL**. No hay límite de tamaño de textura artificial ni compresión desactivada "por web". No tocar nada acá. (El único caso a vigilar: si algún día metés una textura *grande no-pixel* tipo fondo/cielo fotográfico, ESA sí podría querer VRAM compression — pero hoy no aplica.)

---

## 6. CPU vs GPU — qué corre dónde

| Trabajo | Dónde corre hoy | ¿Está bien? | Comentario |
|---|---|---|---|
| Tinte foot-light del rig del player | **CPU** — `LightField.sample()` 1×/frame (`player.gd:345`) | ✅ Sí | 1 sample/frame con ≤64 luces, falloff simple. Trivial. |
| Empaquetado de luces a uniforms | **CPU** — `pack_lights()` 1×/frame (`light_field.gd:39`) | ✅ Sí | Buffers pre-alocados, sin GC churn. Ya optimizado. |
| Luz por-píxel de caras de muro + entidades | **GPU** — `wall_face.gdshader` | ✅ Sí | Bien: lo pesado (por-fragmento) está en GPU. |
| Generación de textura de charco del player | **CPU** — `_apply_light_tex` (`player.gd:126-146`), bucle 256×256 | ✅ Sí (con matiz) | Solo corre al **cambiar un knob (tecla L)** o si `player_soft≠2.0`; con el default usa la textura horneada (`light_pool.tres`) y **no genera nada**. No es per-frame. OK. |
| Visibilidad / niebla | **CPU** — `dungeon_fog.update_visibility`, gateada por celda | ✅ Sí | Solo rebarre las ~169 celdas cuando el player cruza de celda, no cada frame. Bien optimizado. |
| Minimap reveal | **CPU** — gateado por celda (`minimap.gd:207`) | ✅ Sí | Mismo patrón de gate. OK. |
| Estela del orbe/bolt | **CPU** — `CPUParticles2D` (`projectile.gd:68`) | ⚠️ Mejorable | **Único candidato claro a mover a GPU.** |
| Motes / hechizos | **GPU** — `GPUParticles2D` | ✅ Sí | Ya en GPU. |
| FX de fuego (burn/fogata/aoe) | **CPU** — sprites animados + tweens | ✅ OK | Es arte pixel; el costo es bajo (pocos sprites). No mover (rompería estilo). |

**Hotspots por-frame:** ninguno preocupante. El sistema de luz fue claramente optimizado (buffers pre-alocados, gates por celda). El único trabajo CPU "tonto" recurrente es la estela CPUParticles del proyectil, y solo cuando hay proyectiles vivos.

**Veredicto CPU/GPU:** **está bien.** Lo pesado (luz por-píxel) está en GPU; lo CPU es liviano y gateado. Mover la estela del bolt a GPU es el único ajuste.

---

## 7. Otros settings (MSAA / vsync / FPS / escala)

- **MSAA 2D:** ausente = off. **Activar ×2 (o ×4)** — quick win #1 (sección 1).
- **vsync / max_fps:** no hay `Engine.max_fps` ni override de vsync en código. Por default Godot usa vsync on. En un .exe desktop conviene **fijar un cap explícito** (p.ej. `Engine.max_fps = 144` o seguir el refresh) para no quemar GPU en menús/pantallas estáticas. Bajo riesgo, alta cortesía con la laptop.
- **HDR 2D:** ya on (`project.godot:125`). ✅
- **Render scale / FSR:** es 2D pixel-art a resolución nativa → **no aplica** escala de render / FSR. No tocar.
- **TAA:** es 3D-only, no aplica a 2D. Ignorar.
- **`post_fx.gdshader`:** sharpen/exposición disponible pero desconectado (sección 3).

---

## 8. "¿Qué motores / lenguaje mejorarían el juego?"

**Respuesta honesta: quedate en Godot 4.6 + GDScript.** Para este scope (iso 2D dungeon-crawler, ≤64 luces, decenas de mobs) GDScript es más que suficiente y el código ya está optimizado donde importa.

Dónde *sí* tendría sentido otra herramienta (y dónde no):
- **C# / GDExtension (C++/Rust):** solo valdría si el **procgen** (`dungeon_gen.gd`) o el pathfinding (`AStarGrid`) se volvieran un cuello de botella al generar pisos enormes. Hoy **no lo son** (se genera 1 piso por transición, no por frame). **No reescribir.**
- **Compute shaders (Forward+ los habilita ahora):** tentador para el sistema de luz o para simular muchísimas partículas. Pero el sistema de luz ya corre por-fragmento en GPU vía `wall_face.gdshader` (que es lo correcto para 2D), y las partículas GPU nativas alcanzan. Un compute shader sería **sobreingeniería** para este scope.
- **El verdadero "upgrade de motor" ya pasó:** Compatibility → Forward+. Eso desbloqueó glow 2D, HDR 2D, GPUParticles2D completas y shaders 2D sin restricciones. Lo que falta es **usar** esas capacidades (MSAA, afinar glow, subir la estela a GPU), no cambiar de motor/lenguaje.

---

## No tocar / riesgoso (tentador pero peligroso)

- **NO reescribir el modelo de luz a PointLight2D nativo + normal-maps.** No era un workaround de WebGL; es el look foot-lit deliberado (entidades unshaded, caras de muro con sombra de esquina). Cambiarlo rompe la estética pulida y es el subsistema marcado **sensible** en `AGENTS.md`. El costo CPU actual es trivial.
- **NO comprimir las texturas pixel-art a VRAM (DXT/ETC) ni activar mipmaps.** El Lossless + Nearest + no-mipmaps es correcto para pixel-art, no una limitación heredada de WebGL.
- **NO convertir los FX de fuego (burn/fogata/AoE) de arte pixel a GPUParticles genéricas.** El arte pixel es de Felipe y es el estilo final; las partículas GPU solo deben *sumar* (chispas/humo), no reemplazar.
- **NO activar FXAA/screen_space_aa** en pixel-art: emborrona. Usar MSAA 2D, no FXAA.
- **Cuidado con `snap_2d_transforms_to_pixel`** con la cámara que sigue al player: puede dar jitter. Testear, no asumir.
- **Subir `MAX_LIGHTS`** requiere cambiarlo en `light_field.gd:17` Y `wall_face.gdshader:11` **a la vez**; desincronizarlos rompe el packing. Solo hacerlo si se nota el corte de luces.

---

## Checklist priorizado

**Hacer ya (seguro, barato, alto impacto):**
- [ ] Activar **MSAA 2D ×2** (probar ×4) en `project.godot` → `rendering/anti_aliasing/quality/msaa_2d`. Validar con Felipe que no emborrona el pixel-art.
- [ ] Subir la **estela del bolt** `CPUParticles2D → GPUParticles2D` (`scripts/projectile.gd:68`).
- [ ] Fijar **`Engine.max_fps`** explícito en un autoload (evita 1000fps en menús).

**Afinar (look, con Felipe, bajo riesgo):**
- [ ] Tunear **glow** del Environment (`main.tscn:67-69`): bajar `glow_hdr_threshold` ~1.0, sumar `glow_levels/strength/bloom` para el bloom de bolts/auras/fuego.
- [ ] Decidir **`post_fx.gdshader`**: cablearlo (ColorRect full-screen en `FX`) para saturación/exposición, o borrarlo (hoy es código muerto).
- [ ] Opcional cosmético: turbulencia/sub-emitters/collision en GPUParticles (chispas del AoE, humo del burn) — solo si suma sin pisar el arte.

**Vigilar (no actuar salvo que se note):**
- [ ] `MAX_LIGHTS` 64→128 solo si topás el cap con muchas luces (cambiar en los **dos** archivos).
- [ ] Si algún día entra una textura grande no-pixel (fondo fotográfico), evaluar VRAM compression solo para esa.

**No tocar:** modelo de luz custom, import de texturas pixel-art, FX de fuego pixel-art. (Ver sección anterior.)

---

### Estado de los settings clave (referencia rápida)

| Setting | Valor hoy | OK / Acción |
|---|---|---|
| Renderer | Forward+ (`project.godot:15`) | ✅ |
| Driver Windows | d3d12 (`project.godot:124`) | ✅ |
| HDR 2D | on (`project.godot:125`) | ✅ |
| Glow 2D | on, intensity 0.7, threshold 1.2 (`main.tscn:67-69`) | ✅ (afinar) |
| Texture filter | Nearest (`project.godot:123`) | ✅ |
| Compresión textura | Lossless, sin mipmaps | ✅ (correcto para pixel-art) |
| MSAA 2D | **ausente = off** | ⬆️ **Activar** |
| screen_space_aa (FXAA) | off | ✅ dejar off |
| max_fps / vsync | sin override | ⬆️ fijar cap |
| post_fx.gdshader | existe, **no cableado** | decidir: cablear o borrar |
| Estela del bolt | CPUParticles2D (`projectile.gd:68`) | ⬆️ subir a GPU |
