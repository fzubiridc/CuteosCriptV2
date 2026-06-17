shader_type canvas_item;
// Post-proceso de pantalla para 2D: saturación + exposición (brillo).
// El WorldEnvironment en 2D solo aplica glow; tonemap/adjustments NO afectan al 2D,
// así que esto se hace leyendo el screen texture y reescribiéndolo.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float saturation = 1.0;   // 0 = gris, 1 = normal, >1 = más saturado
uniform float exposure = 1.0;     // 1 = sin cambio, >1 = más brillo

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * exposure;
	float l = dot(c, vec3(0.299, 0.587, 0.114));   // luminancia
	c = mix(vec3(l), c, saturation);
	COLOR = vec4(c, 1.0);
}
