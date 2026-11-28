shader_type spatial;

uniform vec4 felt_center : source_color = vec4(0.047, 0.310, 0.255, 1.0);
uniform vec4 felt_edge : source_color = vec4(0.024, 0.173, 0.145, 1.0);
uniform vec4 trim_gold : source_color = vec4(0.784, 0.659, 0.384, 1.0);
uniform float half_side = 14.0;
uniform float detail_mode : hint_range(0.0, 1.0) = 1.0;

varying vec2 cloth;

void vertex() {
	cloth = VERTEX.xz;
}

void fragment() {
	// 细腻双频丝绒织布暗纹（无摩尔纹闪烁）
	float grain;
	if (detail_mode > 0.5) {
		vec2 weave_uv = vec2(cloth.x + cloth.y, cloth.x - cloth.y) * vec2(31.0, 29.0);
		// Fade subpixel threads before they can alias as the camera moves.
		vec2 weave_fade = vec2(1.0) - smoothstep(vec2(0.6), vec2(2.6), fwidth(weave_uv));
		grain = sin(weave_uv.x) * weave_fade.x * 0.026
			+ sin(weave_uv.y) * weave_fade.y * 0.012;
	} else {
		float weave_a = sin(cloth.x * 58.0) * sin(cloth.y * 54.0);
		float weave_b = sin((cloth.x + cloth.y) * 31.0) * sin((cloth.x - cloth.y) * 29.0);
		grain = weave_a * 0.016 + weave_b * 0.010;
	}

	// Keep the cloth nearly uniform, with only a subtle natural color transition.
	float radial = clamp(length(cloth) / max(1.0, half_side * 1.18), 0.0, 1.0);
	float spotlight = smoothstep(0.0, 1.0, radial);
	vec3 base = mix(felt_center.rgb, felt_edge.rgb, spotlight * 0.35);

	// 紧贴红木围栏内沿的凹槽暗影，增强立体层次
	float edge_dist = half_side - max(abs(cloth.x), abs(cloth.y));
	float inner_ao = mix(0.86, 1.0, smoothstep(0.0, 0.32, edge_dist));
	if (detail_mode > 0.5) {
		float sheen = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		base += felt_center.rgb * vec3(1.12, 1.05, 0.92) * sheen * 0.06;
		inner_ao = mix(0.80, 1.0, smoothstep(0.0, 0.32, edge_dist));
	}

	// 新中式极细暗金内收双线（紧贴最外沿，绝不干扰任何牌区）
	float line_outer = smoothstep(0.055, 0.0, abs(edge_dist - 0.36));
	float line_inner = smoothstep(0.038, 0.0, abs(edge_dist - 0.58));
	float corner_accent = step(half_side - 2.4, max(abs(cloth.x), abs(cloth.y))) * step(half_side - 2.4, min(abs(cloth.x), abs(cloth.y)));
	float gold_line = max(line_outer * 0.30, line_inner * 0.14) + line_inner * corner_accent * 0.18;
	if (detail_mode > 0.5) {
		gold_line = max(line_outer * 0.50, line_inner * 0.30) + line_inner * corner_accent * 0.28;
	}

	vec3 col = base * (1.0 + grain) * inner_ao;
	col = mix(col, trim_gold.rgb, clamp(gold_line, 0.0, detail_mode > 0.5 ? 0.64 : 0.38));

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, clamp(gold_line, 0.0, 1.0));
	SPECULAR = mix(0.10, 0.36, clamp(gold_line, 0.0, 1.0));
	if (detail_mode > 0.5) {
		float gold_polish = clamp(gold_line * 1.8, 0.0, 1.0);
		ROUGHNESS = mix(0.96, 0.24, gold_polish);
		SPECULAR = mix(0.12, 0.62, gold_polish);
		METALLIC = gold_polish * 0.50;
	}
}
