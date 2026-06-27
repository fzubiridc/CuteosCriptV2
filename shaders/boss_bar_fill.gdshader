shader_type canvas_item;
// Relleno de la barra de jefe: recorta de IZQUIERDA→DERECHA según fill_ratio y
// ondula el borde derecho (la "superficie" del líquido) para dar efecto de oleaje.

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float wave_amplitude_px : hint_range(0.0, 16.0) = 4.0;
uniform float wave_frequency : hint_range(0.5, 12.0) = 3.0;
uniform float wave_speed : hint_range(0.0, 10.0) = 2.6;

void fragment() {
	vec4 liquid = texture(TEXTURE, UV);
	float tex_w = max(1.0, float(textureSize(TEXTURE, 0).x));
	float amp = wave_amplitude_px / tex_w;

	// Olas verticales que viajan en Y → chapotean contra el borde derecho.
	float phase = UV.y * 6.2831853 * wave_frequency;
	float wave = sin(phase + TIME * wave_speed) * amp;
	wave += sin(phase * 1.7 - TIME * wave_speed * 0.6) * amp * 0.35;

	// La superficie (borde derecho del líquido) está en x = fill_ratio.
	float surface = fill_ratio + wave;
	float softness = 1.5 / tex_w;
	float inside = 1.0 - smoothstep(surface - softness, surface + softness, UV.x);
	inside *= step(0.001, fill_ratio);

	COLOR = vec4(liquid.rgb, liquid.a * inside);
}
