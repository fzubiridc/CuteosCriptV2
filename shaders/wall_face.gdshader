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
uniform float normal_strength = 1.0;
uniform float relief_floor = 0.65;   // 1.0 = sin relieve; más bajo = relieve más marcado
uniform sampler2D normal_tex : repeat_disable;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 albedo = texture(TEXTURE, UV);
	vec3 n = texture(normal_tex, UV).xyz * 2.0 - 1.0;
	n.xy *= normal_strength;
	n = normalize(n);

	vec3 acc = ambient;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) { break; }
		float rad = light_radius[i];
		if (rad <= 0.0) { continue; }
		vec2 delta = light_pos[i] - world_pos;
		float d = length(delta);
		if (d >= rad) { continue; }
		float att = pow(1.0 - d / rad, 2.0) * light_energy[i];
		// Relieve: luz en (dx, dy, altura) contra la normal del ladrillo.
		vec3 ldir = normalize(vec3(delta, max(light_height[i], 1.0)));
		float ndl = max(dot(n, ldir), 0.0);
		float relief = mix(relief_floor, 1.0, ndl);
		acc += light_color[i] * att * relief;
	}

	// Cap preservando el tono (igual que LightField.sample).
	float m = max(acc.r, max(acc.g, acc.b));
	if (m > cap) { acc *= cap / m; }

	COLOR = vec4(albedo.rgb * acc, albedo.a);
}
