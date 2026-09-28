// Céu procedural: gradiente, brilho do pôr do sol, sol, lua, estrelas, nuvens e montanhas distantes em camadas.
// scripts/day_night.gd atualiza cores e direções todo quadro. `horizon` é também a cor da névoa: o terreno
// distante some nela e abaixo do horizonte o céu tem a mesma cor, então não há emenda.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.24, 0.48, 0.85);
uniform vec3 horizon : source_color = vec3(0.71, 0.84, 0.95);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float day : hint_range(0.0, 1.0) = 1.0;   // 0 = noite, 1 = dia
uniform float cloud_time = 0.0;
uniform vec3 fog_color : source_color = vec3(0.71, 0.84, 0.95);   // névoa do momento (escura em caverna, vermelha no submundo)
uniform float cave = 0.0;   // 0 ao ar livre, 1 debaixo da terra: o céu some na cor da névoa
uniform sampler2D noise : repeat_enable, filter_linear;   // ruído contínuo (seamless), 0..1

const vec3 SUN_COLOR = vec3(1.0, 0.93, 0.7);
const vec3 DUSK_COLOR = vec3(1.0, 0.48, 0.22);
// Montanhas de trás para a frente: frequência ao redor do horizonte, base, amplitude e névoa (mais longe = mais azul e clara).
const float M_FREQ[3] = float[3](5.0, 2.0, 3.0);
const float M_BASE[3] = float[3](0.030, 0.012, 0.0);
const float M_AMP[3] = float[3](0.12, 0.22, 0.20);
const float M_HAZE[3] = float[3](0.80, 0.62, 0.42);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float el = d.y;
	float night = 1.0 - smoothstep(0.05, 0.55, day);
	// Perto do nascer/pôr do sol o horizonte esquenta, mais forte do lado do sol.
	float dusk = (1.0 - smoothstep(0.0, 0.4, abs(sun_dir.y))) * smoothstep(-0.25, -0.02, sun_dir.y);
	float side = max(dot(normalize(d.xz + 1e-5), normalize(sun_dir.xz + 1e-5)), 0.0);
	float band = 1.0 - smoothstep(0.0, 0.5, el);

	vec3 col = mix(horizon, zenith, pow(clamp(el, 0.0, 1.0), 0.5));
	col += DUSK_COLOR * dusk * band * (pow(side, 2.5) * 0.85 + 0.1) * step(0.0, el);

	// Estrelas: um ponto sorteado em cada célula da grade de direções; só à noite.
	if (night > 0.0 && el > 0.0) {
		vec3 sp = d * 80.0;
		vec3 id = floor(sp);
		float h = hash13(id);
		if (h > 0.982) {
			vec3 off = vec3(hash13(id + 7.1), hash13(id + 13.7), hash13(id + 3.3)) - 0.5;
			float r = length(fract(sp) - 0.5 - off * 0.6);
			float twinkle = 0.65 + 0.35 * sin(TIME * 2.5 + h * 90.0);
			col += vec3(0.92, 0.95, 1.0) * smoothstep(0.16, 0.0, r) * twinkle * night * smoothstep(0.0, 0.2, el);
		}
	}

	// Sol: disco, coroa e brilho largo.
	float sd = dot(d, sun_dir);
	float sun_vis = smoothstep(-0.06, 0.02, sun_dir.y);
	col += SUN_COLOR * (smoothstep(0.9990, 0.9994, sd) * 1.5 + pow(max(sd, 0.0), 40.0) * 0.45 + pow(max(sd, 0.0), 5.0) * 0.1) * sun_vis;

	// Lua: disco com crateras (ruído) e um halo azulado.
	float md = dot(d, moon_dir);
	vec3 mt = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
	vec2 mp = vec2(dot(d, mt), dot(d, cross(moon_dir, mt)));
	float moon_vis = smoothstep(-0.06, 0.02, moon_dir.y);
	vec3 moon_col = vec3(0.88, 0.91, 1.0) * (0.72 + 0.4 * texture(noise, mp * 22.0).r);
	col = mix(col, moon_col, smoothstep(0.99925, 0.99935, md) * moon_vis);
	col += vec3(0.45, 0.55, 0.9) * pow(max(md, 0.0), 60.0) * 0.3 * moon_vis * night;

	// Nuvens: duas camadas de ruído projetadas num plano; a de cima é mais fina e rápida.
	if (el > 0.0) {
		vec3 cloud_day = mix(vec3(0.16, 0.19, 0.3), vec3(1.0), day);
		vec2 wind = vec2(cloud_time * 0.004, cloud_time * 0.0015);
		vec2 uv = d.xz / (el + 0.28) * 0.2 + wind;
		float cover = smoothstep(0.5, 0.66, texture(noise, uv).r);
		float shade = 1.0 - 0.32 * smoothstep(0.5, 0.75, texture(noise, uv + sun_dir.xz * 0.02).r);
		vec3 cc = cloud_day * shade + DUSK_COLOR * dusk * pow(side, 2.0) * 0.45;
		col = mix(col, cc, cover * smoothstep(0.0, 0.16, el) * 0.93);
		vec2 uv2 = d.xz / (el + 0.12) * 0.34 + wind * 2.5 + 0.5;
		float thin = smoothstep(0.56, 0.75, texture(noise, uv2).r);
		col = mix(col, cloud_day + DUSK_COLOR * dusk * 0.2, thin * smoothstep(0.02, 0.3, el) * 0.42);
	}

	// Montanhas distantes: silhuetas ao redor do horizonte, misturadas à névoa (mais longe, mais névoa).
	float az = atan(d.z, d.x) / 6.2831853;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 u = vec2(az * M_FREQ[i], fi * 0.31);
		float n = 0.65 * texture(noise, u).r + 0.35 * texture(noise, vec2(u.x * 3.0 + 0.37, u.y + 0.5)).r;
		float top = M_BASE[i] + M_AMP[i] * n;
		if (el > 0.0 && el < top) {
			vec3 tone = mix(vec3(0.13, 0.25, 0.22), vec3(0.25, 0.36, 0.5), fi == 0.0 ? 1.0 : (fi == 1.0 ? 0.5 : 0.0));
			tone = tone * mix(0.14, 1.0, day) + DUSK_COLOR * dusk * 0.12;
			vec3 m = mix(tone, horizon, M_HAZE[i]);
			m = mix(horizon, m, smoothstep(0.0, 0.035, el));   // a base some na névoa
			col = m;
		}
	}
	COLOR = mix(col, fog_color, cave);
}
