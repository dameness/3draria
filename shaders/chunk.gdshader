// Blocos: textura do atlas × luz. Cor do vértice: r = luz do céu (já com o tom da face e a oclusão ambiente),
// g = luz das fontes (tocha, orbe, cristal...), a = cor dela, b = tipo (0 bloco, 0.25 chama de tocha, 0.5 planta que balança ao vento, 1 brilha sozinho, como a lava).
// O dia/noite muda só `daylight`, `sky_tint` e `light_dir` (sol de dia, lua de noite): as faces viradas para
// a luz ficam mais claras e as tochas continuam acesas à noite.
shader_type spatial;
render_mode unshaded;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float daylight = 1.0;
uniform vec3 sky_tint = vec3(1.0);
uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 aura = vec4(0.0);      // luz que anda com o jogador (poções Brilho e Coruja): xyz = posição no mundo, w = raio
uniform vec3 aura_color = vec3(1.0, 0.92, 0.75);
uniform float aura_power = 0.0;    // 0 = sem aura

varying vec3 wpos;
varying vec3 wworld;
varying float facing;
varying vec3 tone;    // sol quente nas faces viradas para a luz, sombra fria nas outras
varying vec3 wnormal;
varying vec3 hue;     // cor da luz das fontes (alfa do vértice: 3+3+2 bits, ver ChunkMesher.pack_hue)

void vertex() {
	wpos = VERTEX;
	wworld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sun = dot(NORMAL, light_dir);
	facing = 0.84 + 0.16 * sun;
	tone = mix(vec3(0.84, 0.90, 1.10), vec3(1.08, 1.02, 0.90), sun * 0.5 + 0.5);
	wnormal = NORMAL;
	int q = int(COLOR.a * 255.0 + 0.5);
	hue = vec3(float(q >> 5) / 7.0, float((q >> 2) & 7) / 7.0, float(q & 3) / 3.0);
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
	// Cada bloco um tom um pouco diferente + manchas largas: quebra o "carpete" de textura repetida.
	vec3 cell = floor(wworld - wnormal * 0.01);
	float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	t.rgb *= 0.91 + 0.10 * h + 0.07 * sin(cell.x * 0.21 + cell.z * 0.13 + cell.y * 0.4) * sin(cell.z * 0.17 - cell.x * 0.09);
	if (COLOR.b > 0.9) {
		ALBEDO = t.rgb * (1.05 + 0.18 * sin(TIME * 2.0 + wpos.x * 2.3 + wpos.z * 1.7));
	} else {
		vec3 sky = COLOR.r * daylight * sky_tint * facing * tone;
		float flicker = 0.93 + 0.07 * sin(TIME * 9.0 + wpos.x * 0.7 + wpos.z * 0.9);   // a luz das tochas tremula
		vec3 torch = COLOR.g * flicker * hue;
		if (aura_power > 0.0) {
			float near = clamp(1.0 - distance(wworld, aura.xyz) / aura.w, 0.0, 1.0);
			torch = max(torch, aura_color * near * aura_power);
		}
		ALBEDO = t.rgb * max(max(sky, torch), vec3(0.03));
		if (abs(COLOR.b - 0.25) < 0.05) {   // chama da tocha
			ALBEDO = t.rgb * (1.1 + 0.3 * sin(TIME * 13.0 + wpos.x * 9.0 + wpos.z * 7.0));
		}
	}
}
