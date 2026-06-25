shader_type canvas_item;
// Minimapa circular con anillo ornamental dorado en el borde. Recorta a círculo
// (alpha 0 afuera) y pinta un aro dorado en el contorno. Preserva textura × modulate.

void fragment() {
	float d = length(UV - vec2(0.5));
	float clip = smoothstep(0.5, 0.46, d);                 // recorte circular suave
	// Anillo dorado entre d≈0.45 y 0.5.
	float ring = smoothstep(0.45, 0.47, d) * (1.0 - smoothstep(0.485, 0.5, d));
	vec3 gold = vec3(0.82, 0.66, 0.30);
	COLOR.rgb = mix(COLOR.rgb, gold, clamp(ring, 0.0, 1.0));
	COLOR.a *= max(clip, ring);
}
