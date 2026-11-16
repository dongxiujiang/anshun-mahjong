shader_type spatial;
varying vec3 world_point;
uniform vec4 felt_color : source_color = vec4(0.045, 0.135, 0.145, 1.0);
uniform sampler2D fibers : filter_linear_mipmap, repeat_enable;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 cloth = world_point.xz;
	float fiber = texture(fibers, cloth * vec2(0.045, 0.072)).r;
	float nap = texture(fibers, cloth * 0.012).r;
	float edge = smoothstep(0.45, 1.0, length(cloth / vec2(25.0, 22.0)));
	ALBEDO = felt_color.rgb * (0.94 + 0.12 * fiber + 0.05 * nap - 0.10 * edge);
	float ring = 1.0 - smoothstep(0.012, 0.048, abs(length(cloth) - 4.0));
	ALBEDO *= 1.0 + 0.08 * ring;
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
}
