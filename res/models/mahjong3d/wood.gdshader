shader_type spatial;
varying vec3 local_point;
void vertex() {
	local_point = VERTEX;
}
void fragment() {
	vec2 plank = abs(local_point.x) > abs(local_point.z) ? local_point.zx : local_point.xz;
	float line = plank.y * 49.0 + sin(plank.x * 1.3 + plank.y) * 1.7 + sin(plank.x * 2.9) * 0.28;
	float grain = 0.07 * sin(line) + 0.06 * sin(line * 0.39 + plank.x * 0.35);
	ALBEDO = vec3(0.26, 0.15, 0.088) * (1.0 + grain);
	ROUGHNESS = 0.48;
	SPECULAR = 0.28;
}
