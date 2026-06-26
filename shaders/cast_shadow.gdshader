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
uniform float width_grow = 0.0;  // cuánto se ENSANCHA la silueta en abanico hacia la punta

float samp(sampler2D tex, vec2 uv, vec2 px, float r) {
	// Blur en disco: centro + 2 anillos de 8 muestras (interior r*0.5, exterior r)
	// con pesos tipo gaussiano → difusión suave de verdad, sin "fantasmas"/escalones
	// al subir el radio (a diferencia de la cruz de 9 taps anterior).
	float a = texture(tex, uv).a * 0.18;
	float wsum = 0.18;
	for (int k = 0; k < 8; k++) {
		float ang = float(k) * 0.78539816;          // 2π/8
		vec2 d = vec2(cos(ang), sin(ang));
		a += texture(tex, uv + d * px * (r * 0.5)).a * 0.072;
		a += texture(tex, uv + d * px * r).a * 0.043;
		wsum += 0.115;
	}
	return a / wsum;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float along = clamp(UV.y / max(feet_v, 0.001), 0.0, 1.0);  // 1 pies, 0 punta
	// pérdida hacia la punta + difuminado en la base (los pies → lo cubre el contacto)
	float env_base = 1.0 - smoothstep(1.0 - base_fade, 1.0, along);
	float fade = pow(along, tip_fade) * env_base;
	float r = blur * (1.0 + blur_grow * (1.0 - along));        // más blur hacia la punta
	// Ensanche en abanico: magnifica la silueta horizontalmente hacia la punta (along→0).
	// spread=1 en los pies, 1+width_grow en la punta. Samplea hacia el centro → más ancha sin clipear.
	float spread = 1.0 + width_grow * (1.0 - along);
	vec2 uv2 = vec2((UV.x - 0.5) / spread + 0.5, UV.y);
	float a = samp(TEXTURE, uv2, px, r);
	COLOR = vec4(0.0, 0.0, 0.0, a * fade * strength);
}
