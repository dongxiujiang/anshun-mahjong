shader_type spatial;

uniform vec4 felt_center : source_color = vec4(0.047, 0.310, 0.255, 1.0);
uniform vec4 felt_edge : source_color = vec4(0.024, 0.173, 0.145, 1.0);
uniform vec4 trim_gold : source_color = vec4(0.784, 0.659, 0.384, 1.0);
uniform float half_side = 14.0;

varying vec2 cloth;

void vertex() {
	cloth = VERTEX.xz;
}

void fragment() {
	// 细腻双频丝绒织布暗纹（无摩尔纹闪烁）
	float weave_a = sin(cloth.x * 58.0) * sin(cloth.y * 54.0);
	float weave_b = sin((cloth.x + cloth.y) * 31.0) * sin((cloth.x - cloth.y) * 29.0);
	float grain = weave_a * 0.016 + weave_b * 0.010;

	// 真实牌桌柔和顶灯中心漫射光晕 + 边角收暗
	float radial = clamp(length(cloth) / max(1.0, half_side * 1.18), 0.0, 1.0);
	float spotlight = smoothstep(0.0, 1.0, radial);
	vec3 base = mix(felt_center.rgb, felt_edge.rgb, spotlight * 0.85);

	// 紧贴红木围栏内沿的凹槽暗影，增强立体层次
	float edge_dist = half_side - max(abs(cloth.x), abs(cloth.y));
	float inner_ao = mix(0.62, 1.0, smoothstep(0.0, 0.55, edge_dist));

	// 新中式极细暗金内收双线（紧贴最外沿，绝不干扰任何牌区）
	float line_outer = smoothstep(0.055, 0.0, abs(edge_dist - 0.36));
	float line_inner = smoothstep(0.038, 0.0, abs(edge_dist - 0.58));
	float corner_accent = step(half_side - 2.4, max(abs(cloth.x), abs(cloth.y))) * step(half_side - 2.4, min(abs(cloth.x), abs(cloth.y)));
	float gold_line = max(line_outer * 0.30, line_inner * 0.14) + line_inner * corner_accent * 0.18;

	vec3 col = base * (1.0 + grain) * inner_ao;
	col = mix(col, trim_gold.rgb, clamp(gold_line, 0.0, 0.38));

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, clamp(gold_line, 0.0, 1.0));
	SPECULAR = mix(0.10, 0.36, clamp(gold_line, 0.0, 1.0));
}
