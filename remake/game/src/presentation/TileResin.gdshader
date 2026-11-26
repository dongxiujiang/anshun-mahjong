shader_type spatial;

// Preserve the approved source model's UV islands and engraved artwork.
uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D engraving : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool printed = true;
uniform vec4 ivory : source_color = vec4(0.98, 0.97, 0.92, 1.0);
uniform vec4 green : source_color = vec4(0.18, 0.44, 0.29, 1.0);
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.84, 0.38);

void fragment() {
	vec3 ink = texture(artwork, UV).rgb;
	float green_back = step(0.73, UV.y) * step(ink.r * 1.6, ink.g) * step(ink.b * 1.6, ink.g);
	vec3 face = ink * ivory.rgb * 0.93;
	if (!printed && UV.y < 0.73) face = ivory.rgb * 0.93;
	vec3 back_col = green.rgb * (0.78 + ink.g * 0.38);
	ALBEDO = mix(face, back_col, green_back);
	// 细腻树脂光泽：牌面略柔防反光刺眼，牌背玉石温润有质感
	ROUGHNESS = mix(0.52, 0.34, green_back);
	SPECULAR = mix(0.24, 0.38, green_back);
	NORMAL_MAP = texture(engraving, UV).rgb;
	NORMAL_MAP_DEPTH = printed ? 0.14 : 0.0;
	if (glow_amount > 0.001) {
		EMISSION = glow_color * glow_amount * mix(0.38, 0.22, green_back);
	}
}
