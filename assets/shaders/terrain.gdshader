shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// Territory: 12 circles packed as (x, z, radius, owner).
uniform float zones[48];
uniform int zone_count = 0;
uniform vec4 iran_color : source_color = vec4(0.2, 0.42, 0.9, 1.0);
uniform vec4 turan_color : source_color = vec4(0.85, 0.25, 0.2, 1.0);
uniform float grid_alpha = 0.0;
uniform vec4 ghost = vec4(0.0, 0.0, 0.0, 0.0); // x, z, half size, valid (1 ok / -1 bad / 0 off)

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// vertex colours are authored in sRGB
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	// fine ground speckle so the colour field does not look flat
	float sp = hash(floor(wpos.xz * 3.0));
	c *= 0.93 + sp * 0.12;

	float d_iran = 1e5;
	float d_turan = 1e5;
	for (int i = 0; i < 12; i++) {
		if (i >= zone_count) break;
		float d = length(wpos.xz - vec2(zones[i * 4], zones[i * 4 + 1])) - zones[i * 4 + 2];
		if (zones[i * 4 + 3] < 0.5) d_iran = min(d_iran, d); else d_turan = min(d_turan, d);
	}
	float band_i = 1.0 - smoothstep(0.0, 0.45, abs(d_iran));
	float band_t = 1.0 - smoothstep(0.0, 0.45, abs(d_turan));
	if (d_iran < 0.0) c = mix(c, iran_color.rgb, 0.07);
	if (d_turan < 0.0) c = mix(c, turan_color.rgb, 0.07);
	c = mix(c, iran_color.rgb * 1.2, band_i * 0.85);
	c = mix(c, turan_color.rgb * 1.2, band_t * 0.85);

	if (grid_alpha > 0.0 && d_iran < 0.0) {
		vec2 g = abs(fract(wpos.xz / 2.0) - 0.5);
		float line = 1.0 - smoothstep(0.44, 0.49, max(g.x, g.y));
		c = mix(c, vec3(1.0, 0.95, 0.8), (1.0 - line) * grid_alpha);
	}
	if (ghost.w != 0.0) {
		vec2 q = abs(wpos.xz - ghost.xy);
		if (max(q.x, q.y) < ghost.z) {
			c = mix(c, ghost.w > 0.0 ? vec3(0.35, 0.95, 0.45) : vec3(1.0, 0.25, 0.2), 0.5);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
