shader_type canvas_item;
// Minimapa con forma de ROMBO ISOMÉTRICO (diamante achatado) + anillo ornamental dorado en el borde.
// Recorta al rombo (alpha 0 afuera) y pinta un aro dorado en el contorno. Preserva textura × modulate.
// draw_ring: 1 = dibuja el aro dorado (fondo exterior); 0 = solo recorta (el mapa, para no tener DOS aros).
// iso_ratio: ancho/alto del rombo (2 = iso clásico del juego, bien achatado; más alto = más chato).

uniform float draw_ring = 1.0;
uniform vec2 box_size = vec2(150.0);   // tamaño en px del recuadro (para normalizar la posición local)
uniform float iso_ratio = 2.0;         // ancho/alto del rombo (achatamiento)

// Recortamos por la POSICIÓN LOCAL del vértice (no por UV): con AtlasTexture la UV viene remapeada
// a la región del mapa, no al recuadro → la forma quedaba descentrada y el mapa se salía.
varying vec2 vlocal;

void vertex() {
	vlocal = VERTEX;
}

void fragment() {
	vec2 p = vlocal / box_size - vec2(0.5);                       // [-0.5, 0.5] en ambos ejes
	// Rombo ISO (diamante achatado): |x|/0.5 + |y|/(0.5/iso_ratio) = 1 en el borde.
	float d = abs(p.x) / 0.5 + abs(p.y) / (0.5 / iso_ratio);
	float clip = smoothstep(1.0, 0.94, d);                        // recorte suave al rombo
	// Anillo dorado justo en el contorno del rombo (solo si draw_ring).
	float ring = smoothstep(0.92, 0.96, d) * (1.0 - smoothstep(0.98, 1.0, d)) * draw_ring;
	vec3 gold = vec3(0.82, 0.66, 0.30);
	COLOR.rgb = mix(COLOR.rgb, gold, clamp(ring, 0.0, 1.0));
	COLOR.a *= max(clip, ring);
}
