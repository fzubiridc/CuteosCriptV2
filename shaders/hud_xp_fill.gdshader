shader_type canvas_item;

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float fill_start : hint_range(0.0, 1.0) = 0.195;
uniform float fill_end : hint_range(0.0, 1.0) = 0.768;
uniform float shine_interval : hint_range(1.0, 10.0) = 4.0;
uniform float shine_duration : hint_range(0.2, 2.0) = 0.85;
uniform float shine_width : hint_range(0.005, 0.1) = 0.025;
uniform float shine_strength : hint_range(0.0, 2.0) = 0.75;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float edge = mix(fill_start, fill_end, fill_ratio);
	float fill_mask = step(UV.x, edge) * step(fill_start, UV.x);

	float cycle_time = mod(TIME, shine_interval);
	float shine_active = 1.0 - step(shine_duration, cycle_time);
	float shine_progress = clamp(cycle_time / shine_duration, 0.0, 1.0);
	float shine_position = mix(fill_start, fill_end, shine_progress);
	float diagonal_x = UV.x + (UV.y - 0.5) * 0.035;
	float shine = 1.0 - smoothstep(0.0, shine_width, abs(diagonal_x - shine_position));
	shine *= shine_active * fill_mask * tex.a;

	tex.rgb += vec3(1.0, 0.72, 0.28) * shine * shine_strength;
	tex.a *= fill_mask;
	COLOR = tex;
}
