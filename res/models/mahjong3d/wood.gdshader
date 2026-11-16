shader_type spatial;
varying vec3 local_point;
void vertex() {
	local_point = VERTEX;
}
void fragment() {
	vec2 plank = abs(local_point.x) > abs(local_point.z) ? local_point.zx : local_point.xz;
	float line = plank.y * 30.0 + sin(plank.x * 1.3 + plank.y) * 1.7 + sin(plank.x * 2.9) * 0.28;
	float grain = 0.035 * sin(line) + 0.025 * sin(line * 0.39 + plank.x * 0.35);
	vec3 walnut = vec3(0.19, 0.105, 0.061) * (1.0 + grain);
	float edge = max(abs(local_point.x), abs(local_point.z));
	float inlay = (1.0 - smoothstep(0.012, 0.040, abs(edge - 14.52))) * smoothstep(0.18, 0.40, local_point.y);
	ALBEDO = mix(walnut, vec3(0.42, 0.31, 0.15), inlay);
	ROUGHNESS = mix(0.65, 0.42, inlay);
	SPECULAR = 0.20;
}
