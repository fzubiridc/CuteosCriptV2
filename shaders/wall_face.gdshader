shader_type canvas_item;
render_mode unshaded;

// Luz POR PÍXEL para las caras de muro (foot-lit). Replica el modelo de
// LightField (suma de luces con falloff²) pero por fragmento, y agrega
// relieve por normal-map (NdotL por luz). Las luces llegan como uniforms
// desde dungeon.gd cada frame. Unshaded → no la afecta la sombra del occluder,
// así mantenemos: piso iluminado + cara iluminada + sombra desde la esquina,
// AHORA con gradiente por píxel y relieve.

const int MAX_LIGHTS = 64;
const int MAX_WALL_SPANS = 96;

uniform int light_count = 0;
uniform vec2 light_pos[MAX_LIGHTS];
uniform vec3 light_color[MAX_LIGHTS];
uniform float light_energy[MAX_LIGHTS];
uniform float light_radius[MAX_LIGHTS];
uniform float light_height[MAX_LIGHTS];
uniform vec3 ambient = vec3(0.1, 0.1, 0.12);
uniform float cap = 1.4;
uniform float light_boost = 1.0;   // multiplica el aporte de luz (caras de muro)
uniform float light_falloff = 2.0; // exponente de caída de la luz (bajo = más difusa/suave)
uniform float normal_strength = 1.0;
uniform float relief_floor = 0.65;   // 1.0 = sin relieve; más bajo = relieve más marcado
uniform sampler2D normal_tex : repeat_disable;

// --- Cara direccional (muros iso) ---
// En vez de la normal del normal-map, la cara usa una normal PLANA que apunta hacia
// la cámara (+Y = hacia el usuario). Así el NdotL apaga la cara cuando la luz está del
// lado opuesto (detrás del muro) → una cara que da al usuario no se ilumina con la luz
// que está del lado del personaje. La componente z controla cuánto la ALTURA de la luz
// "levanta" la cara trasera (z bajo = back más oscuro).
uniform bool use_face_normal = false;
uniform vec3 face_normal = vec3(0.0, 1.0, 0.6);
// Solo muros iso: proyecta cada pixel a la linea de contacto con el piso antes
// de medir la distancia a la luz. Corrige que el brillo trepe por el sprite.
uniform bool wall_base_projection = false;
uniform bool wall_span_projection = false;
uniform int wall_span_count = 0;
uniform vec2 wall_span_a[MAX_WALL_SPANS];
uniform vec2 wall_span_b[MAX_WALL_SPANS];
uniform vec2 wall_floor_origin = vec2(0.0);
uniform vec2 wall_floor_u_axis = vec2(128.0, 64.0);
uniform vec2 wall_floor_v_axis = vec2(-128.0, 64.0);
// Solo muros iso: compensacion lateral por cara. No mueve la luz real ni el
// charco del piso; solo corrige la posicion que este shader usa para la cara.
uniform bool wall_face_offset = false;
uniform float wall_face_offset_px = 28.0;
uniform float wall_face_offset_start = 32.0;
uniform float wall_face_offset_full = 220.0;
// Debug manual: 1 = UV del tile, 2 = linea de base detectada.
uniform int wall_debug_view = 0;

varying vec2 world_pos;
varying vec2 world_y_axis;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	world_y_axis = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
}

float wall_base_y_px(vec2 uv, vec2 tex_size, float left_a, float right_a, float center_bottom_a) {
	float x = clamp(uv.x, 0.0, 1.0);
	float w = tex_size.x;
	float h = tex_size.y;

	// Los sources de muro actuales son texturas sueltas de 1 tile. La base no
	// es y=1: es la silueta inferior del arte (diagonal/V segun pieza).
	if (h > 230.0) {
		if (left_a > right_a) {
			return mix(247.0, 191.0, x); // corner_ne_se
		}
		return mix(191.0, 247.0, x);     // corner_nw_sw
	}

	if (w > 200.0) {
		float mid = 1.0 - abs(x * 2.0 - 1.0);
		if (center_bottom_a > 0.1) {
			return mix(135.0, 199.0, mid); // corner_se_sw
		}
		return mix(191.0, 143.0, mid);     // corner_nw_ne
	}

	if (left_a > right_a) {
		return mix(191.0, 135.0, x); // highwall / NW art
	}
	return mix(135.0, 191.0, x);     // wall_ne / NE art
}

vec2 wall_offset_dir(vec2 tex_size, float left_a, float right_a) {
	float w = tex_size.x;
	float h = tex_size.y;

	// Esquinas: tienen dos caras en un mismo sprite; evitar un corrimiento unico
	// que arregle una mitad y rompa la otra.
	if (w > 170.0 || h > 230.0) {
		return vec2(0.0);
	}

	if (left_a > right_a) {
		return normalize(vec2(-2.0, 1.0)); // highwall / NW art: hacia SW
	}
	return normalize(vec2(2.0, -1.0));     // wall_ne / NE art: hacia NE
}

vec2 closest_on_segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float denom = dot(ab, ab);
	if (denom <= 0.0001) {
		return a;
	}
	float t = clamp(dot(p - a, ab) / denom, 0.0, 1.0);
	return a + ab * t;
}

vec2 screen_to_floor(vec2 p) {
	vec2 d = p - wall_floor_origin;
	float det = wall_floor_u_axis.x * wall_floor_v_axis.y - wall_floor_u_axis.y * wall_floor_v_axis.x;
	if (abs(det) <= 0.0001) {
		return d;
	}
	return vec2(
		(d.x * wall_floor_v_axis.y - d.y * wall_floor_v_axis.x) / det,
		(wall_floor_u_axis.x * d.y - wall_floor_u_axis.y * d.x) / det
	);
}

vec2 floor_to_screen(vec2 p) {
	return wall_floor_origin + wall_floor_u_axis * p.x + wall_floor_v_axis * p.y;
}

vec2 closest_on_segment_floor(vec2 p, vec2 a, vec2 b) {
	vec2 pf = screen_to_floor(p);
	vec2 af = screen_to_floor(a);
	vec2 bf = screen_to_floor(b);
	return floor_to_screen(closest_on_segment(pf, af, bf));
}

vec2 wall_span_base_pos(vec2 p) {
	vec2 best = p;
	float best_d = 1e20;
	for (int i = 0; i < MAX_WALL_SPANS; i++) {
		if (i >= wall_span_count) { break; }
		vec2 q = closest_on_segment_floor(p, wall_span_a[i], wall_span_b[i]);
		vec2 pf = screen_to_floor(p);
		vec2 qf = screen_to_floor(q);
		float d = dot(pf - qf, pf - qf);
		if (d < best_d) {
			best_d = d;
			best = q;
		}
	}
	return best;
}

void fragment() {
	vec4 albedo = texture(TEXTURE, UV);
	bool debug_out = false;
	vec4 debug_color = vec4(0.0);
	if (wall_debug_view == 1) {
		debug_out = true;
		debug_color = vec4(UV.x, UV.y, 0.0, albedo.a);
	}

	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	float left_a = texture(TEXTURE, vec2(0.04, 0.94)).a;
	float right_a = texture(TEXTURE, vec2(0.96, 0.94)).a;
	float center_bottom_a = texture(TEXTURE, vec2(0.5, 0.985)).a;
	vec2 light_sample_pos = world_pos;
	float wall_z = 0.0;
	if (wall_span_projection && wall_span_count > 0) {
		light_sample_pos = wall_span_base_pos(world_pos);
		wall_z = length(world_pos - light_sample_pos);
	} else if (wall_base_projection) {
		float base_y = wall_base_y_px(UV, tex_size, left_a, right_a, center_bottom_a);
		float y_px = UV.y * tex_size.y;
		float lift_px = max(base_y - y_px, 0.0);
		light_sample_pos = world_pos + world_y_axis * lift_px;
		wall_z = length(world_y_axis * lift_px);
		if (wall_debug_view == 2) {
			float line = 1.0 - smoothstep(0.0, 2.0, abs(y_px - base_y));
			debug_out = true;
			debug_color = vec4(line, UV.y, 1.0 - line, albedo.a);
		}
	}

	vec2 offset_dir = vec2(0.0);
	if (wall_face_offset) {
		offset_dir = wall_offset_dir(tex_size, left_a, right_a);
	}

	if (debug_out) {
		COLOR = debug_color * COLOR;
	} else {
	vec3 n;
	if (use_face_normal) {
		n = normalize(face_normal);   // cara plana direccional (mira a la cámara)
	} else {
		n = texture(normal_tex, UV).xyz * 2.0 - 1.0;
		n.xy *= normal_strength;
		n = normalize(n);
	}

	vec3 acc = ambient;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) { break; }
		float rad = light_radius[i];
		if (rad <= 0.0) { continue; }
		vec2 lpos = light_pos[i];
		if (wall_face_offset) {
			float od = length(lpos - light_sample_pos);
			float ot = smoothstep(wall_face_offset_start, wall_face_offset_full, od);
			lpos += offset_dir * wall_face_offset_px * ot;
		}
		vec2 delta = lpos - light_sample_pos;
		float d = wall_base_projection ? length(vec3(delta, wall_z)) : length(delta);
		if (d >= rad) { continue; }
		float att = pow(1.0 - d / rad, light_falloff) * light_energy[i];
		// Direccionalidad de la cara.
		float ndl;
		if (use_face_normal) {
			// Facing 2D PURO: independiente de distancia y de la ALTURA de la luz. Clave →
			// una luz cercana DETRÁS del muro no debe iluminar la cara por su componente de
			// altura (ese era el bug). >0 = luz del lado que mira la cara; <0 = detrás.
			float facing = dot(normalize(face_normal.xy), normalize(delta));
			ndl = clamp(facing, 0.0, 1.0);
		} else {
			// Relieve por normal-map: luz en (dx, dy, altura) contra la normal del ladrillo.
			vec3 ldir = normalize(vec3(delta, max(light_height[i], 1.0)));
			ndl = max(dot(n, ldir), 0.0);
		}
		float relief = mix(relief_floor, 1.0, ndl);
		acc += light_color[i] * att * relief * light_boost;
	}

	// Cap preservando el tono (igual que LightField.sample).
	float m = max(acc.r, max(acc.g, acc.b));
	if (m > cap) { acc *= cap / m; }

	// Multiplicar por COLOR (modulate/self_modulate/vertex) preserva el flash de
	// daño y el color base del Polygon2D → este shader sirve igual para las caras
	// de muro y para las entidades (enemigos/boss).
	COLOR = vec4(albedo.rgb * acc, albedo.a) * COLOR;
	}
}
