shader_type canvas_item;
render_mode blend_mix, unshaded;
// Sombra proyectada: difusión (blur de la silueta) + pérdida de fuerza a lo largo
// del largo (fuerte en los pies, se desvanece hacia la punta) + más blur hacia la
// punta. La intensidad global de ESTA sombra (según distancia a la luz) llega por
// `strength`. La silueta se estira a lo largo de su eje Y → UV.y mapea la posición
// a lo largo de la sombra: UV.y≈feet_v en los pies, UV.y→0 en la punta.

uniform float feet_v = 0.8;      // UV.y de la base (pies)
uniform float strength = 0.6;    // intensidad de esta sombra (prox a la luz)
uniform float tip_fade = 1.3;    // curva de pérdida hacia la punta (mayor = cae antes)
uniform float base_fade = 0.18;  // fracción del largo, desde los pies, que arranca difuminada
uniform float blur = 1.6;        // radio base de difusión (texels)
uniform float blur_grow = 3.0;   // cuánto crece el blur hacia la punta

float samp(sampler2D tex, vec2 uv, vec2 px, float r) {
	float a = texture(tex, uv).a * 0.28;
	a += texture(tex, uv + vec2(px.x * r, 0.0)).a * 0.12;
	a += texture(tex, uv - vec2(px.x * r, 0.0)).a * 0.12;
	a += texture(tex, uv + vec2(0.0, px.y * r)).a * 0.12;
	a += texture(tex, uv - vec2(0.0, px.y * r)).a * 0.12;
	a += texture(tex, uv + vec2(px.x * r, px.y * r)).a * 0.06;
	a += texture(tex, uv - vec2(px.x * r, px.y * r)).a * 0.06;
	a += texture(tex, uv + vec2(px.x * r, -px.y * r)).a * 0.06;
	a += texture(tex, uv - vec2(px.x * r, -px.y * r)).a * 0.06;
	return a;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float along = clamp(UV.y / max(feet_v, 0.001), 0.0, 1.0);  // 1 pies, 0 punta
	// pérdida hacia la punta + difuminado en la base (los pies → lo cubre el contacto)
	float env_base = 1.0 - smoothstep(1.0 - base_fade, 1.0, along);
	float fade = pow(along, tip_fade) * env_base;
	float r = blur * (1.0 + blur_grow * (1.0 - along));        // más blur hacia la punta
	float a = samp(TEXTURE, UV, px, r);
	COLOR = vec4(0.0, 0.0, 0.0, a * fade * strength);
}
