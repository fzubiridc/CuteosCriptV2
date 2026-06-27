# Sistema de FX de hechizos — Plan de diseño

- **Fecha:** 2026-06-27
- **Target:** ejecutable desktop (`.exe`), render **Forward+** (sin límites de Compatibility/web).
- **Estado:** diseño cerrado en papel, **apuntando a 9–10** (capa PRO+ incluida, §12). Implementación **pendiente** (hay un refactor en curso; arrancar solo con OK de Felipe).
- **Objetivo:** pasar de FX hardcodeado en `projectile.gd` a un sistema **data-driven** donde sumar un elemento = crear un `.tres`. Nada de "lo que hacía el pixi" (legacy): se diseña PRO desde el estado actual del Godot.

---

## 0. Decisiones cerradas

| Tema | Decisión |
|---|---|
| **CPU vs GPU** | **GPUParticles2D** (Forward+ = set completo: turbulencia, sub-emitters, collision, attractors). |
| **Alcance del ElementProfile** | **Tema de TODO el elemento** (bolt, impacto, AoE/nova, DoT/burn, aura) = single source of truth. Bolt se implementa primero; el resto se engancha después. |
| **Origen del elemento** | **El arma / staff** (campo `element` en la def del arma, en `Data.gd`). |
| **Núcleo del bolt** | **Híbrido**: default = orbe **procedural** tintado por el elemento; el arma puede traer un sprite propio como override. Criterio de éxito: el procedural tiene que verse pro en la escena de test (ver §10); si no, se usa sprite. |
| **Roster inicial** | **Fuego + Arcano** (2 perfiles). Hielo y Rayo quedan para después. |
| **Glow/bloom** | **WorldEnvironment → Glow 2D** (firme, ahora que es desktop) + capas additive (`FxMaterials`). |
| **Juice / game feel** | Impacto **coreografiado** + hitstop (2–4 frames) en hits potentes; configurable por perfil. |
| **Objetivo de calidad** | **9–10**, no 7. Ver §12 "Capa PRO+". |

---

## 1. Principios

1. **Datos ⟂ Lógica ⟂ Arte.** El `.tres` (datos) configura el componente `SpellFX` (lógica) que usa 3–7 texturas en gris (arte). El motor anima y tinta.
2. **El motor anima lo estático.** El artista dibuja piezas chiquitas en gris; Godot las emite, mueve, escala, desvanece, rota y tinta por color ramp.
3. **Additive-first + glow.** El look "mágico" sale de capas additive + bloom HDR, no de dibujar luz a mano.
4. **Escalable.** Agregar un elemento o aplicar el tema a un sistema nuevo (AoE, aura) = datos, no código nuevo.

---

## 2. Contexto técnico

- Render **Forward+** (`config/features = "4.6","Forward Plus"`, d3d12). `viewport/hdr_2d=true`.
- Ya existe el autoload **`FxMaterials`** con `add_unshaded()` (BLEND_ADD + UNSHADED) y `mix_unshaded()`.
- Hoy el trail es un `CPUParticles2D` con 12 partículas estáticas (velocity 0) creado inline en `projectile.gd` — funcional pero sub-configurado y no sistémico.
- Assets pixel-art, `default_texture_filter=0` (nearest). Cámara zoom 3×.

---

## 3. Arquitectura

### 3.1 `ElementProfile` (Resource) — single source of truth del elemento

```gdscript
class_name ElementProfile extends Resource

# — Identidad
@export var id: StringName                  # "fuego" / "arcano"
@export var display_name: String

# — Paleta (tinta TODO el elemento: bolt, impacto, AoE, DoT, aura)
@export var color_core: Color               # centro casi blanco
@export var color_mid:  Color               # color saturado del elemento
@export var color_tail: Color               # cola → transparente
@export var ramp_override: Gradient         # opcional: degradé bicolor (ej. arcano magenta+cian)

# — Núcleo del bolt (híbrido)
@export_enum("procedural", "sprite") var core_mode := "procedural"
@export var core_texture: Texture2D         # usado si core_mode=="sprite" y el arma no trae override
@export var core_scale := 1.0
@export var core_spin  := 0.0               # rad/s

# — Estela / ribbon (Line2D)
@export var ribbon_enabled := true
@export var ribbon_points := 14
@export var ribbon_width  := 10.0
@export var ribbon_width_curve: Curve       # taper cabeza→cola

# — Partículas del trail (GPUParticles2D)
@export var particle_texture: Texture2D     # chispa/shard/puff EN GRIS
@export var amount := 28
@export var lifetime := 0.35
@export var spread_deg := 25.0
@export var speed_min := 10.0
@export var speed_max := 40.0
@export var backdrift := 0.10               # fracción de -velocidad del bolt
@export var scale_curve: Curve              # escala sobre la vida
@export var turbulence := 0.0
@export var gravity := Vector2.ZERO         # ej. fuego: hacia arriba
@export var subemit_sparkle := false        # micro-destellos al morir (GPU sub-emitter)
@export var use_attractor := false          # vórtice/updraft (GPUParticlesAttractor2D)

# — Luz que viaja
@export var light_color: Color
@export var light_energy := 1.2
@export var light_radius_scale := 1.0

# — Impacto
@export var impact_amount := 28
@export var impact_speed  := 140.0
@export var impact_flash  := 1.6
@export var impact_collide := false         # las partículas del burst chocan con piso/muros
@export var impact_decal: Texture2D         # scorch / rune en piso (gris)
@export var impact_decal_ttl := 2.0
@export var impact_shake   := 0.0           # 0 = off
@export var impact_hitstop := 0.0           # ms de freeze, 0 = off
@export var impact_shockwave: Texture2D     # onda expansiva  [PRO+]
@export var impact_residual_light := 0.6    # la luz del flash decae, no corta seca  [PRO+]

# — Shaders opcionales (la frutilla)
@export var distortion_shader: Shader       # heat-haze (fuego) / refracción (hielo)
@export var ribbon_shader: Shader           # energía scrolleante (arcano)

# ───────── PRO+ (game feel / vida — ver §12) ─────────
@export_group("Cast / muzzle")
@export var cast_time := 0.18               # windup antes de disparar
@export var cast_converge := true           # partículas convergen al foco del staff
@export var muzzle_texture: Texture2D       # flash en la punta al disparar
@export var muzzle_scale := 1.0
@export_group("HDR")
@export var core_hdr_boost := 2.0           # multiplica el color del core (>1 = el glow lo revienta)
@export_group("Vida & variación")
@export var stretch_by_velocity := 0.0      # squash & stretch del core según velocidad
@export var jitter_scale := 0.0
@export var jitter_rot := 0.0
@export var jitter_hue := 0.0               # variación de tono por disparo
@export var light_flicker := 0.0            # 0 = constante; >0 parpadea/pulsa
@export var spawn_ease: Curve               # scale-in con overshoot
@export_group("Audio (por capa)")
@export var sfx_cast: AudioStream
@export var sfx_travel_loop: AudioStream
@export var sfx_impact: AudioStream

# — Tema para otros sistemas (se enganchan después; bolt es prioridad)
@export_group("AoE / nova (futuro)")
@export var aoe_tint: Color
@export var aoe_particle: Texture2D
@export_group("DoT / burn (futuro)")
@export var dot_tint: Color
@export var dot_frames: Array[Texture2D]
@export_group("Aura (futuro)")
@export var aura_tint: Color
```

### 3.2 `SpellFX` (componente reusable) — `scripts/fx/spell_fx.gd` + `scenes/fx/spell_fx.tscn`

Se enchufa a cualquier proyectil/hechizo; lee un `ElementProfile` y se autoconfigura.

```
SpellFX (Node2D)
├─ Core      (Sprite2D, additive)      # procedural tintado, o sprite override del arma
├─ Ribbon    (Line2D)                  # width_curve + gradient; _process empuja posiciones recientes
├─ Particles (GPUParticles2D)          # ParticleProcessMaterial armado desde el profile
└─ Light     (PointLight2D)            # color/energía del profile
```

API mínima:
- `apply(profile: ElementProfile, weapon_override: Texture2D = null)` → arma todas las capas.
- `set_velocity(v: Vector2)` cada frame → alimenta el `backdrift` de la lluvia y empuja la ribbon.

### 3.3 `SpellImpact` (one-shot, auto-free) — `scenes/fx/spell_impact.tscn`

Lo dispara el **mismo** `ElementProfile` → el hit se siente de la misma familia que el trail.

```
SpellImpact (Node2D, auto-free)
├─ Burst (GPUParticles2D, one_shot=true)   # + collision opcional
├─ Flash (PointLight2D, tween energy→0)
├─ Decal (Sprite2D, z bajo, fade por TTL)  # scorch/rune en el piso
└─ Boom  (AnimatedSprite2D, opcional)      # reusa frames existentes si el arma los trae
```
Efectos globales opcionales: `shake` (cámara) y `hitstop` (freeze breve), según el profile.

---

## 4. Las capas del trail

1. **Núcleo (Core).** Híbrido: por defecto un orbe glow procedural tintado con `color_core`; si el arma trae sprite, se usa ese. Additive, opcional spin.
2. **Estela (Ribbon).** `Line2D` alimentado por las N posiciones recientes del bolt, con `width_curve` (taper cabeza→cola) y gradiente del elemento. La "cola de cometa" coherente.
3. **Lluvia (Particles).** `GPUParticles2D`: chispas/brasas que derivan hacia atrás (`backdrift`) con scatter, color ramp + `scale_curve` sobre la vida, turbulencia y (opcional) sub-emitter para destellos y attractor para vórtice/updraft.
4. **Luz (Light).** `PointLight2D` de color que viaja con el bolt e ilumina piso/paredes.
5. **Glow global (WorldEnvironment).** Bloom HDR: todo lo additive (núcleo, chispas) sangra luz. Es el mayor salto de look; va una sola vez a nivel escena.

---

## 5. Recetas por elemento (roster inicial)

| | 🔥 Fuego | 🔮 Arcano |
|---|---|---|
| core / mid / tail | `#FFF2C0 / #FF7A1E / #6E1B05` | `#F3E2FF / #B14FFF / #3A0F7A` |
| ramp | cálido | **bicolor** (magenta `#B14FFF` + cian `#79E0FF`) |
| textura partícula | `puff` + `spark` | `core_glow` + `spark` |
| backdrift / turbulencia | bajo (0.06) / **alta** | medio (0.10) / media |
| gravity | hacia **arriba** (lenguas) | 0 |
| attractor | updraft (tira hacia arriba) | **vórtice orbital** |
| sub-emitter | chispas que saltan | twinkles |
| luz | `#FF6A20`, energía 1.4 | `#B14FFF`, energía 1.3 |
| impacto | `scorch` oscuro + collision sparks + shake leve + **heat-haze** | `rune` + burst bicolor + **ribbon-energía** shader |
| vibe | caótico, asciende | etéreo, brillante, dos tonos |

**Futuros:** Hielo (cyan, shard, recto/cortante, hitstop en impacto, refracción) · Rayo (amarillo, zigzag, instantáneo, textura arc).

---

## 6. Arte a crear (todo en gris/blanco — el motor tinta)

Para Fuego + Arcano alcanza con:

| PNG | px | uso |
|---|---|---|
| `core_glow` | 64 | núcleo procedural + partículas suaves (o reusar el radial procedural actual) |
| `spark` | 24 | chispas (fuego y arcano) |
| `puff` | 48 | humo/brasa (fuego) |
| `scorch` | 96 | decal de impacto en piso (fuego) |
| `rune` | 96 | decal de impacto en piso (arcano) |

→ **5 PNG** cubren los dos elementos. Hielo sumaría `shard` + `frost`; Rayo sumaría `arc`. Nearest filter, fondo transparente.
Ubicación: `assets/fx/particles/` y `assets/fx/decals/`.

---

## 7. Integración con el código actual

- **`Data.gd`**: cada arma/staff gana `element: ElementProfile` (+ opcional `bolt_sprite_override`).
- **`player.gd`**: en vez de `set_bolt_frames(...)`, pasa el `ElementProfile` del arma al proyectil.
- **`projectile.gd`**:
  - instancia `SpellFX` y llama `fx.apply(element, weapon_override)` en el setup;
  - `fx.set_velocity(velocity)` en `_physics_process`;
  - en el impacto, spawnea `SpellImpact` con el mismo `element`;
  - se **borran** los bloques hardcoded (`FRIENDLY_COL`, gradientes a mano, el `CPUParticles2D` inline).
- Detrás de un flag al principio (`USE_SPELL_FX`) para comparar contra el trail actual sin romper nada.

---

## 8. Performance

- **Object pool** de proyectiles e impactos (no instanciar/liberar en caliente).
- GPU `one_shot` para impactos; trail con emisión continua y `local_coords=false`.
- Cap global de partículas si alguna vez hay bullet-hell (no urgente en ARPG normal).

---

## 9. Fases de ejecución (post-refactor)

- **F0** — `ElementProfile` (con campos PRO+) + 2 `.tres` (fuego, arcano) + las 5 texturas en gris.
- **F1** — `SpellFX` (núcleo + ribbon + partículas + luz) en el **FX Lab** (`scenes/fx/spell_fx_test.tscn`, con sliders) **y HDR push + WorldEnvironment Glow desde ya** (el procedural se juzga *con* bloom, no sin él). Acá se decide procedural vs sprite (§10). No toca el juego.
- **F2** — **Vida del bolt:** squash & stretch, jitter/variación, flicker de luz, easing de spawn/fade.
- **F3** — **Nacimiento:** cast/windup (reusa `mage/power`) + muzzle flash.
- **F4** — **`SpellImpact` coreografiado:** secuencia (flash → onda → burst → residuo → decal) + collision + luz residual + hitstop/shake.
- **F5** — **Audio por capa** (cast / travel-loop / impact).
- **F6** — Integrar en `projectile.gd` detrás del flag `USE_SPELL_FX`; cablear `element` en `Data.gd`/armas; migrar lo hardcoded.
- **F7** — Shaders opcionales (heat-haze, ribbon-energía) + pooling.
- **F8** — **Legibilidad:** color language jugador/enemigo; FX que no tapa telegraphs.
- *(Futuro)* — Hielo/Rayo; enganchar el tema a AoE/nova/DoT/aura.

---

## 10. Criterio de éxito del núcleo procedural

Felipe está escéptico de que el orbe **procedural** quede a la altura. Regla:
- En **F1**, el núcleo procedural + partículas tiene que verse **pro en el FX Lab con HDR push + WorldEnvironment Glow ON** (juzgarlo sin bloom es injusto). Mostrar, no afirmar.
- Si convence → queda como default (cero arte de bolt por elemento).
- Si **no** convence → el arma usa `bolt_sprite_override` (sprite hecho a mano). El diseño híbrido ya deja esa puerta abierta sin reescribir nada.

---

## 11. Defaults / convenciones

- Código: `scripts/fx/` (`element_profile.gd`, `spell_fx.gd`, `spell_impact.gd`). Escenas: `scenes/fx/`.
- Assets: `assets/fx/particles/`, `assets/fx/decals/`.
- Z/iso depth: respeta convenciones actuales (trail detrás del orbe, decal en piso bajo muros, impacto por encima).
- Juice: el game feel coreografiado (§12) se prende por perfil; los valores arrancan suaves y se suben en el FX Lab.

---

## 12. Capa PRO+ (de 7 a 9–10)

Estas 9 mejoras separan "buen FX" de "FX memorable". Todas se enganchan como **campos del `ElementProfile` + capas del `SpellFX`** — no rompen la arquitectura.

### Las 4 que más mueven la aguja
1. **Ciclo de vida completo.** cast/windup (partículas convergen al `focus` del staff + glow creciente, reusando `mage/power`) → **muzzle flash** en la punta → travel → impacto. Que se sienta *lanzado*, no que aparezca. Campos: `cast_time`, `cast_converge`, `muzzle_texture`.
2. **HDR + bloom selectivo.** Core con `core_hdr_boost > 1.0` para que el WorldEnvironment Glow muerda **solo** donde querés. Casi gratis (ya hay `hdr_2d`), look "caro".
3. **Audio por capa.** `sfx_cast / sfx_travel_loop / sfx_impact` (autoload `Audio`). Un trail sin sonido está muerto.
4. **Impacto coreografiado.** Secuencia ~300 ms: flash 1 frame → onda (`impact_shockwave`) → burst → humo residual → decal + **luz residual** que decae (`impact_residual_light`); + **hitstop** 2–4 frames en hits potentes. El timing es el arte.

### Pulido que se nota
5. **Squash & stretch** del núcleo por velocidad (`stretch_by_velocity`).
6. **Variación por disparo** (`jitter_scale/rot/hue`) + **flicker de luz** (`light_flicker`) → anti-"stampeado".
7. **Easing/overshoot** en spawn (`spawn_ease`) y fade — nada lineal.

### Workflow (calidad sostenida)
8. **FX Lab** — escena con sliders para tunear ElementProfiles **en vivo** (estilo `serve.py`/tabs). Se construye como el banco de pruebas en F1 y se expande. Iterar rápido = calidad real.
9. **Legibilidad de gameplay** — color language jugador vs enemigo; el FX **no tapa** telegraphs enemigos. Pasada de balance visual al final.
