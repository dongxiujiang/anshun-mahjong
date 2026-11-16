shader_type spatial;
render_mode unshaded;
varying vec2 position;
void vertex() {
	position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
	float light = 1.0 - smoothstep(8.0, 42.0, length(position * vec2(0.75, 1.0)));
	ALBEDO = mix(vec3(0.085, 0.13, 0.14), vec3(0.14, 0.22, 0.21), light);
}
