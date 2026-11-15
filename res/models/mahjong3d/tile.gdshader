shader_type spatial;
uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D engraving : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec4 ivory : source_color = vec4(0.98, 0.96, 0.88, 1.0);
uniform vec4 green : source_color = vec4(0.20, 0.46, 0.12, 1.0);
void fragment() {
	vec3 ink = texture(artwork, UV).rgb;
	// The green resin lives in the lower UV islands; retain the painted bamboo ink.
	float green_back = step(0.73, UV.y) * step(ink.r * 1.6, ink.g) * step(ink.b * 1.6, ink.g);
	ALBEDO = mix(ink * ivory.rgb * 0.73, green.rgb * (0.8 + ink.g * 0.35), green_back);
	ROUGHNESS = 0.50;
	SPECULAR = 0.24;
	NORMAL_MAP = texture(engraving, UV).rgb;
	NORMAL_MAP_DEPTH = 0.12;
}
