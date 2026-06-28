class_name ElementProfile
extends Resource
## Tema visual de un elemento (single source of truth). Ver docs/spell_fx_plan.md.

# --- Identidad ---
@export var id: StringName = &""
@export var display_name: String = ""

# --- Paleta (el motor tinta TODO con esto) ---
@export var color_core: Color = Color(1, 1, 1)
@export var color_mid: Color = Color(0.6, 0.8, 1.0)
@export var color_tail: Color = Color(0.1, 0.2, 0.5)
@export var color_accent: Color = Color(0, 0, 0, 0)   # 2do tono opcional en el ramp (bicolor, ej. arcano)

# --- Nucleo (hibrido: procedural por defecto, sprite override por arma) ---
@export_enum("procedural", "sprite", "external") var core_mode: String = "procedural"
@export var core_texture: Texture2D
@export var core_scale: float = 0.6
@export var core_spin: float = 0.0
@export var core_hdr_boost: float = 2.0   # >1 = el glow lo revienta

# --- Estela / ribbon ---
@export var ribbon_enabled: bool = true
@export var ribbon_points: int = 14
@export var ribbon_width: float = 10.0
@export var ribbon_width_curve: Curve

# --- Particulas (GPUParticles2D) ---
@export var particle_texture: Texture2D
@export var particle_scale: float = 1.0
@export var bolt_scale: float = 1.0   # escala del bolt de la vara (sViaje de la tool Hechizos); 1.0 = auto
@export var impact_scale: float = 1.0 # escala de la explosion de impacto (sImpacto)
@export var bolt_fps: float = 0.0     # fps de la anim de viaje del bolt (fpsViaje); 0 = default
@export var impact_fps: float = 0.0   # fps de la anim de impacto (fpsImpacto); 0 = default
@export var aura_enabled: bool = false # halo additive opcional detras del bolt (tool: aura)
@export var aura_boost: float = 1.4
@export var amount: int = 28
@export var lifetime: float = 0.4
@export var spread_deg: float = 25.0
@export var speed_min: float = 8.0
@export var speed_max: float = 32.0
@export var gravity: Vector2 = Vector2.ZERO
@export var scale_curve: Curve
@export var turbulence: float = 0.0
@export var orbit_velocity: float = 0.0   # giro orbital de las particulas (arcano)
@export var subemit_sparkle: bool = false

# --- Luz que viaja ---
@export var light_color: Color = Color(0.6, 0.8, 1.0)
@export var light_energy: float = 1.2
@export var light_radius_scale: float = 1.0

# --- Vida / variacion (PRO+) ---
@export var stretch_by_velocity: float = 0.0
@export var jitter_scale: float = 0.0
@export var light_flicker: float = 0.0

# --- Impacto (lo usa SpellImpact, fase siguiente) ---
@export var impact_amount: int = 28
@export var impact_speed: float = 140.0
@export var impact_flash: float = 1.6
@export var impact_decal: Texture2D
@export var impact_shake: float = 0.0
@export var impact_hitstop: float = 0.0

# --- Audio por capa (PRO+) ---
@export var sfx_cast: AudioStream
@export var sfx_travel_loop: AudioStream
@export var sfx_impact: AudioStream
