shader_type spatial;
varying vec3 world_point;
varying vec3 local_point;
uniform vec4 felt_color : source_color = vec4(0.055, 0.175, 0.165, 1.0);
uniform sampler2D fibers : filter_linear_mipmap, repeat_enable;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_point = VERTEX;
}
void fragment() {
	vec2 cloth = world_point.xz;
	float fiber = texture(fibers, cloth * vec2(0.045, 0.072)).r;
	float nap = texture(fibers, cloth * 0.012).r;
	float edge = smoothstep(0.45, 1.0, length(cloth / vec2(25.0, 22.0)));
	float pool = 1.0 - smoothstep(3.0, 24.0, length(cloth * vec2(0.7, 1.0)));
	ALBEDO = felt_color.rgb * (0.88 + 0.10 * fiber + 0.04 * nap + 0.16 * pool - 0.16 * edge);
	float rim = 13.9008 - max(abs(local_point.x), abs(local_point.z));
	float stitch = 1.0 - smoothstep(0.012, 0.033, abs(rim - 0.52));
	ALBEDO = mix(ALBEDO, vec3(0.16, 0.245, 0.195), stitch * 0.45);
	float circle = length(cloth);
	float ring = 1.0 - smoothstep(0.009, 0.028, min(abs(circle - 4.8), abs(circle - 5.0)));
	ALBEDO *= 1.0 + 0.10 * ring;
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
}
