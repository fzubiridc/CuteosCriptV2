shader_type canvas_item;
render_mode unshaded;
// DIAGNÓSTICO BINARIO con ANCLA AL TILE: reconstruye el punto de anclaje del tile
// (centro-piso) desde el UV, colapsando X e Y. Así TODOS los píxeles del muro
// usan UNA sola posición de referencia → el tile entero se ilumina/oscurece como
// unidad (no se parte ni en horizontal ni en vertical). BLANCO si la luz está del
// lado de la cara, NEGRO si está detrás.
uniform vec2 light_xy = vec2(0.0, 0.0);
uniform vec2 face_n = vec2(0.45, 0.8);
uniform vec2 ref_uv = vec2(0.5, 0.467);     // UV del ancla: centro-X, línea de piso (86/184)
uniform vec2 region = vec2(141.0, 184.0);   // tamaño del tile de muro en px
uniform float layer_scale = 0.5;            // escala de la capa Walls

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Llevar este píxel al ancla del tile (un punto fijo por tile).
	vec2 anchor = world_pos - (UV - ref_uv) * region * layer_scale;
	vec2 ldir = normalize(light_xy - anchor);
	float side = dot(normalize(face_n), ldir);
	float b = side > 0.0 ? 1.0 : 0.0;
	vec4 a = texture(TEXTURE, UV);
	COLOR = vec4(b, b, b, a.a);
}
