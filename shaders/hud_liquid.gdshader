shader_type canvas_item;

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float wave_amplitude_px : hint_range(0.0, 8.0) = 2.0;
uniform float wave_frequency : hint_range(0.5, 8.0) = 2.0;
uniform float wave_speed : hint_range(0.0, 8.0) = 1.4;

void fragment() {
	vec4 liquid = texture(TEXTURE, UV);
	float texture_height = max(1.0, float(textureSize(TEXTURE, 0).y));
	float amplitude = wave_amplitude_px / texture_height;
	float phase = UV.x * 6.2831853 * wave_frequency;
	float wave = sin(phase + TIME * wave_speed) * amplitude;
	wave += sin(phase * 1.7 - TIME * wave_speed * 0.65) * amplitude * 0.30;

	// UV.y crece hacia abajo: la superficie baja al perder vida.
	float surface = 1.0 - fill_ratio + wave;
	float softness = 1.25 / texture_height;
	float below_surface = smoothstep(surface - softness, surface + softness, UV.y);
	below_surface *= step(0.001, fill_ratio);
	COLOR = vec4(liquid.rgb, liquid.a * below_surface);
}
