shader_type canvas_item;
render_mode unshaded;

// Luz POR PÍXEL para las caras de muro (foot-lit). Replica el modelo de
// LightField (suma de luces con falloff²) pero por fragmento, y agrega
// relieve por normal-map (NdotL por luz). Las luces llegan como uniforms
// desde dungeon.gd cada frame. Unshaded → no la afecta la sombra del occluder,
// así mantenemos: piso iluminado + cara iluminada + sombra desde la esquina,
// AHORA con gradiente por píxel y relieve.

const int MAX_LIGHTS = 64;

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

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 albedo = texture(TEXTURE, UV);
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
		vec2 delta = light_pos[i] - world_pos;
		float d = length(delta);
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
