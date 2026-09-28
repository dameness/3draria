// Blocos: textura do atlas × luz. Cor do vértice: r = luz do céu (já com o tom da face),
// g = luz de tocha. O dia/noite muda só `daylight` (e a cor `sky_tint`), então tochas continuam acesas à noite.
shader_type spatial;
render_mode unshaded;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float daylight = 1.0;
uniform vec3 sky_tint = vec3(1.0);

void fragment() {
	vec4 t = texture(atlas, UV);
	vec3 sky = COLOR.r * daylight * sky_tint;
	vec3 torch = COLOR.g * vec3(1.0, 0.8, 0.55);
	ALBEDO = t.rgb * max(max(sky, torch), vec3(0.03));
}
