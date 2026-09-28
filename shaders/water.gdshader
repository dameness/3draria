// Superfície da água: translúcida, com ondas suaves e um brilho que corre. Mesma luz dos blocos (cor do vértice:
// r = céu, g = tocha). Fica numa superfície à parte da malha do chunk (ver chunk_mesher.gd).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float daylight = 1.0;
uniform vec3 sky_tint = vec3(1.0);
uniform float alpha = 0.62;

varying vec3 wpos;

void vertex() {
	if (COLOR.b > 0.5) {   // vértice da superfície (b = 1, ver chunk_mesher.gd): ondula
		VERTEX.y += sin(TIME * 1.4 + VERTEX.x * 0.9 + VERTEX.z * 0.7) * 0.035;
	}
	wpos = VERTEX;
}

void fragment() {
	vec3 t = texture(atlas, UV).rgb;
	vec3 sky = COLOR.r * daylight * sky_tint;
	vec3 torch = COLOR.g * vec3(1.0, 0.8, 0.55);
	float glint = smoothstep(0.86, 1.0, sin(wpos.x * 3.1 + TIME * 1.1) * sin(wpos.z * 2.7 - TIME * 0.8));
	ALBEDO = t * max(max(sky, torch), vec3(0.05)) + vec3(0.35) * glint * daylight;
	ALPHA = alpha;
}
