// Modelos voxel (scripts/voxel): cor do vértice (já com a oclusão ambiente); alfa 0 = voxel emissivo, que brilha e pulsa em ondas.
// Dois modos: world_light.x < 0 usa as luzes da cena (personagem, item na mão, com `ambient` como luz mínima); world_light.x >= 0
// é bloco no mundo: luz do céu/tocha do lugar (mesma conta do chunk.gdshader), tom fixo por face e dia/noite em `daylight`/`sky_tint`.
shader_type spatial;
render_mode specular_disabled;

uniform float ambient = 0.35;
uniform float pulse = 0.3;
uniform vec2 world_light = vec2(-1.0, 0.0);   // x = céu, y = tocha
uniform float daylight = 1.0;
uniform vec3 sky_tint = vec3(1.0);

varying float wave;
varying float facing;

void vertex() {
	wave = VERTEX.y * 14.0 + VERTEX.x * 9.0 + VERTEX.z * 7.0;
	facing = NORMAL.y > 0.5 ? 1.0 : NORMAL.y < -0.5 ? 0.55 : NORMAL.z > 0.5 ? 0.9 : NORMAL.z < -0.5 ? 0.7 : 0.8;
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (COLOR.a < 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = c * (1.1 + pulse * sin(TIME * 3.2 + wave));
	} else if (world_light.x >= 0.0) {
		vec3 l = max(max(world_light.x * daylight * sky_tint, world_light.y * vec3(1.0, 0.8, 0.55)), vec3(0.03));
		ALBEDO = vec3(0.0);
		EMISSION = c * facing * l;
	} else {
		ALBEDO = c * (1.0 - ambient);   // `ambient` = parte da cor que não depende da luz (1 = sem sombreamento, como o sprite)
		EMISSION = c * ambient;
	}
}
