// Blocos: textura do atlas × luz. Cor do vértice: r = luz do céu (já com o tom da face),
// g = luz de tocha. O dia/noite muda só `daylight`, então tochas continuam acesas à noite.
shader_type spatial;
render_mode unshaded;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float daylight = 1.0;

void fragment() {
	vec4 t = texture(atlas, UV);
	float sky = COLOR.r * daylight;
	float torch = COLOR.g;
	float light = max(max(sky, torch), 0.03);
	vec3 warm = mix(vec3(1.0), vec3(1.0, 0.8, 0.55), clamp(torch - sky, 0.0, 1.0));
	ALBEDO = t.rgb * light * warm;
}
