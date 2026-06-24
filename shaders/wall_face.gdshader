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
uniform float normal_strength = 1.0;
uniform float relief_floor = 0.65;   // 1.0 = sin relieve; más bajo = relieve más marcado
uniform sampler2D normal_tex : repeat_disable;

// --- Cutout dithered: agujero en el muro cuando el player queda detrás ---
// Elipse anclada al cuerpo del player, con sesgo hacia abajo: la mitad de
// arriba se comprime (up_squash) → el hueco es una cúpula/parábola que abre
// hacia abajo (cubre tu cuerpo) y sube poco → NO agujerea los muros que estás
// tapando vos (los de atrás, cuya base está por encima tuyo).
uniform bool cutout_on = false;
uniform vec2 cutout_pos = vec2(0.0);   // centro del agujero (world coords)
uniform float cutout_w = 55.0;         // medio-ancho del hueco (world units)
uniform float cutout_h = 70.0;         // medio-alto del hueco (world units)
uniform float cutout_up_squash = 3.0;  // 1 = elipse simétrica; más alto = más parábola hacia abajo
uniform float cutout_rot = 0.0;        // rota el hueco (rad) para alinear el squash a la cara del muro iso
uniform float cutout_soft = 0.4;       // ancho del anillo dithered (fracción 0..1 del radio)
uniform float cutout_px = 2.0;         // tamaño de celda del dither (world units; más alto = dither más gordo)

// Bayer 4x4 para el patrón de dither ordenado (estética pixel-art).
const float BAYER[16] = float[](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

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
		acc += light_color[i] * att * relief * light_boost;
	}

	// Cap preservando el tono (igual que LightField.sample).
	float m = max(acc.r, max(acc.g, acc.b));
	if (m > cap) { acc *= cap / m; }

	// Multiplicar por COLOR (modulate/self_modulate/vertex) preserva el flash de
	// daño y el color base del Polygon2D → este shader sirve igual para las caras
	// de muro y para las entidades (enemigos/boss).
	COLOR = vec4(albedo.rgb * acc, albedo.a) * COLOR;

	// Cutout: descarta píxeles del muro en una cúpula dithered sobre el cuerpo del
	// player, revelándolo (se dibujó antes por estar "detrás" en el y-sort).
	if (cutout_on) {
		// cutout_pos ancla en la CABEZA. El hueco abre hacia ABAJO (cubre el cuerpo):
		// arriba de la cabeza (d.y<0) se empuja afuera (sólido) → no toca los muros
		// que tapás vos, que están por encima tuyo.
		vec2 d = world_pos - cutout_pos;
		// Rotar para que el eje del squash siga la diagonal de la cara del muro.
		float ca = cos(cutout_rot);
		float sa = sin(cutout_rot);
		d = vec2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);
		float ny = d.y / cutout_h;            // 0 en la cabeza, 1 abajo (pies)
		if (ny < 0.0) { ny *= cutout_up_squash; }
		// q: 0 en el centro (hueco total) → 1 en el borde de la cúpula → muro sólido.
		float q = length(vec2(d.x / cutout_w, ny));
		float t = smoothstep(1.0 - cutout_soft, 1.0, q);
		int bx = int(mod(floor(world_pos.x / cutout_px), 4.0));
		int by = int(mod(floor(world_pos.y / cutout_px), 4.0));
		float thr = (BAYER[by * 4 + bx] + 0.5) / 16.0;
		COLOR.a *= step(thr, t);   // píxel visible solo si t supera su umbral de dither
	}
}
