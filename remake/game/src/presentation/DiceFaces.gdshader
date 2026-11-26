shader_type spatial;

uniform bool red_die = false;
varying vec2 face_uv;
varying flat int face_number;

void vertex() {
	vec3 outer = VERTEX / 0.19;
	vec3 inner = clamp(outer, vec3(-0.86), vec3(0.86));
	vec3 rounded = normalize(outer - inner);
	// FACE_NORMALS in DiceRoll.gd is also used to read the physical top face.
	if (abs(NORMAL.y) > 0.5) {
		face_number = NORMAL.y > 0.0 ? 1 : 6;
		face_uv = outer.xz;
	} else if (abs(NORMAL.z) > 0.5) {
		face_number = NORMAL.z > 0.0 ? 2 : 5;
		face_uv = outer.xy;
	} else {
		face_number = NORMAL.x > 0.0 ? 3 : 4;
		face_uv = outer.zy;
	}
	VERTEX = 0.19 * (inner + rounded * 0.14);
	NORMAL = rounded;
}

float spot(vec2 at, float radius) {
	float distance_to_edge = length(face_uv - at) - radius;
	float pixel = max(0.005, fwidth(distance_to_edge) * 0.75);
	return 1.0 - smoothstep(-pixel, pixel, distance_to_edge);
}

void fragment() {
	float d = 0.48;
	float radius = 0.205;
	float pips = 0.0;
	if (face_number == 1 || face_number == 3 || face_number == 5)
		pips = spot(vec2(0.0), face_number == 1 ? 0.29 : radius);
	if (face_number >= 2)
		pips = max(pips, max(spot(vec2(-d, d), radius), spot(vec2(d, -d), radius)));
	if (face_number >= 4)
		pips = max(pips, max(spot(vec2(d, d), radius), spot(vec2(-d, -d), radius)));
	if (face_number == 6)
		pips = max(pips, max(spot(vec2(d, 0.0), radius), spot(vec2(-d, 0.0), radius)));
	vec3 body = red_die ? vec3(0.68, 0.05, 0.04) : vec3(0.95, 0.93, 0.86);
	vec3 white_pip = (face_number == 1 || face_number == 4) ? vec3(0.78, 0.08, 0.06) : vec3(0.03, 0.035, 0.04);
	vec3 paint = red_die ? vec3(0.99, 0.96, 0.88) : white_pip;
	ALBEDO = mix(body, paint, pips);
	ROUGHNESS = mix(0.34, 0.52, pips);
	SPECULAR = 0.28;
}
