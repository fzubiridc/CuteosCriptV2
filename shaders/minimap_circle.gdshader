shader_type canvas_item;
// Minimapa circular con anillo ornamental dorado en el borde. Recorta a círculo
// (alpha 0 afuera) y pinta un aro dorado en el contorno. Preserva textura × modulate.
// draw_ring: 1 = dibuja el aro dorado (fondo exterior); 0 = solo recorta a círculo (el mapa,
// para no tener DOS aros concéntricos: el del fondo y el del mapa).

uniform float draw_ring = 1.0;
uniform vec2 box_size = vec2(150.0);   // tamaño en px del recuadro (para normalizar la posición local)

// Recortamos por la POSICIÓN LOCAL del vértice (no por UV): con AtlasTexture la UV viene remapeada
// a la región del mapa, no al recuadro → el círculo quedaba descentrado y el mapa se salía.
varying vec2 vlocal;

void vertex() {
	vlocal = VERTEX;
}

void fragment() {
	float d = length(vlocal / box_size - vec2(0.5));       // recorte circular (en espacio del recuadro)
	float clip = smoothstep(0.5, 0.46, d);                 // recorte circular suave
	// Anillo dorado entre d≈0.45 y 0.5 (solo si draw_ring).
	float ring = smoothstep(0.45, 0.47, d) * (1.0 - smoothstep(0.485, 0.5, d)) * draw_ring;
	vec3 gold = vec3(0.82, 0.66, 0.30);
	COLOR.rgb = mix(COLOR.rgb, gold, clamp(ring, 0.0, 1.0));
	COLOR.a *= max(clip, ring);
}
