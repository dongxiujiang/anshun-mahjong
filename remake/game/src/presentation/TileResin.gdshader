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
	vec3 face = ink * ivory.rgb * 0.78;
	if (green_back < 0.5 && printed) {
		float ink_depth = 1.0 - max(ink.r, max(ink.g, ink.b));
		vec3 carved_ink = max(ink - (vec3(1.0) - ink) * 0.04, vec3(0.0));
		face = carved_ink * ivory.rgb * 0.78 * (1.0 - ink_depth * 0.08);
	}
	if (!printed && UV.y < 0.73) face = ivory.rgb * 0.78;
	vec3 back_col = green.rgb * (0.76 + ink.g * 0.34);
	ALBEDO = mix(face, back_col, green_back);
	// 温润防眩光树脂质感：牌面柔雾不刺眼，牌背保留温润玉釉光泽
	ROUGHNESS = mix(0.48, 0.26, green_back);
	SPECULAR = mix(0.24, 0.44, green_back);
	CLEARCOAT = mix(0.14, 0.56, green_back);
	CLEARCOAT_ROUGHNESS = mix(0.26, 0.12, green_back);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.4);
	ALBEDO += vec3(1.0, 0.91, 0.72) * fresnel * mix(0.005, 0.018, green_back);
	NORMAL_MAP = texture(engraving, UV).rgb;
	NORMAL_MAP_DEPTH = printed ? 0.46 : 0.0;
	if (glow_amount > 0.001) {
		EMISSION = glow_color * glow_amount * mix(0.38, 0.22, green_back);
	}
}
