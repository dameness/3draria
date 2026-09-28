// Blocos: textura do atlas × luz. Cor do vértice: r = luz do céu (já com o tom da face e a oclusão ambiente),
// g = luz de tocha, b = tipo (0 bloco, 0.25 chama de tocha, 0.5 planta que balança ao vento, 1 brilha sozinho, como a lava).
// O dia/noite muda só `daylight`, `sky_tint` e `light_dir` (sol de dia, lua de noite): as faces viradas para
// a luz ficam mais claras e as tochas continuam acesas à noite.
shader_type spatial;
render_mode unshaded;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float daylight = 1.0;
uniform vec3 sky_tint = vec3(1.0);
uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);

varying vec3 wpos;
varying float facing;

void vertex() {
	wpos = VERTEX;
	facing = 0.86 + 0.14 * dot(NORMAL, light_dir);
	if (abs(COLOR.b - 0.5) < 0.1) {
		// Planta: a ponta (parte fracionária de y alta) balança; a base fica parada.
		float tip = step(0.5, fract(VERTEX.y + 0.001));
		VERTEX.x += sin(TIME * 2.0 + VERTEX.x * 1.7 + VERTEX.z * 1.3) * 0.06 * tip;
		VERTEX.z += cos(TIME * 1.7 + VERTEX.z * 1.9 + VERTEX.x * 0.8) * 0.05 * tip;
	}
}

void fragment() {
	vec4 t = texture(atlas, UV);
	if (t.a < 0.5) {
		discard;
	}
	if (COLOR.b > 0.9) {
		ALBEDO = t.rgb * (1.05 + 0.18 * sin(TIME * 2.0 + wpos.x * 2.3 + wpos.z * 1.7));
	} else {
		vec3 sky = COLOR.r * daylight * sky_tint * facing;
		float flicker = 0.93 + 0.07 * sin(TIME * 9.0 + wpos.x * 0.7 + wpos.z * 0.9);   // a luz das tochas tremula
		vec3 torch = COLOR.g * flicker * vec3(1.0, 0.8, 0.55);
		ALBEDO = t.rgb * max(max(sky, torch), vec3(0.03));
		if (abs(COLOR.b - 0.25) < 0.05) {   // chama da tocha
			ALBEDO = t.rgb * (1.1 + 0.3 * sin(TIME * 13.0 + wpos.x * 9.0 + wpos.z * 7.0));
		}
	}
}
