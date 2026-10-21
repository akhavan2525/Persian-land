shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

uniform vec4 shallow : source_color = vec4(0.25, 0.6, 0.68, 1.0);
uniform vec4 deep : source_color = vec4(0.08, 0.27, 0.42, 1.0);
uniform float ice = 0.0;   // 1 = frozen lake

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * 0.6;
	vec2 p = wpos.xz;
	float w1 = sin(p.x * 0.9 + t) * cos(p.y * 0.7 - t * 0.8);
	float w2 = sin(p.x * 2.3 - t * 1.4 + p.y * 1.7);
	NORMAL = normalize((VIEW_MATRIX * vec4(w1 * 0.08 + w2 * 0.04, 1.0, w2 * 0.05, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep.rgb, shallow.rgb, 0.45 + w1 * 0.08);
	ALPHA = mix(0.78, 0.95, fres);
	ROUGHNESS = 0.08;
	if (ice > 0.0) {
		// frozen: still, pale blue-white with faint cracks
		NORMAL = mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, ice);
		float crack = smoothstep(0.92, 1.0, abs(sin(p.x * 0.7 + sin(p.y * 0.5) * 2.0)) * abs(sin(p.y * 0.9 + p.x * 0.2)));
		vec3 ice_col = mix(vec3(0.72, 0.84, 0.92), vec3(0.88, 0.94, 0.98), 0.5 + 0.5 * sin(p.x * 0.13 + p.y * 0.11));
		ALBEDO = mix(ALBEDO, ice_col - crack * 0.12, ice);
		ALPHA = mix(ALPHA, 0.97, ice);
		ROUGHNESS = mix(ROUGHNESS, 0.35, ice);
	}
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
