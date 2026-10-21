shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// Ground layers. Vertex colour holds the layer weights: r = dirt, g = rock, b = sand,
// a = forest floor (darker, mossy grass). Grass fills whatever is left.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Territory: 12 circles packed as (x, z, radius, owner).
uniform float zones[48];
uniform int zone_count = 0;
uniform vec4 iran_color : source_color = vec4(0.2, 0.42, 0.9, 1.0);
uniform vec4 turan_color : source_color = vec4(0.85, 0.25, 0.2, 1.0);
uniform float grid_alpha = 0.0;
// biome: tint on the grass, and how much snow or sand lies over the land
uniform vec3 grass_tint = vec3(1.0);
uniform float snow_cover = 0.0;
uniform float sand_cover = 0.0;
uniform vec4 ghost = vec4(0.0, 0.0, 0.0, 0.0); // x, z, half size, valid (1 ok / -1 bad / 0 off)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	// two scales of grass, the second rotated, so the repeat is not visible
	vec2 uv1 = p / 7.0;
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / 19.0;
	vec4 g1 = texture(grass_tex, uv1);
	vec4 g2 = texture(grass_tex, uv2);
	float macro = texture(grass_tex, p / 160.0).a;
	vec4 grass = mix(g1, g2, 0.35 + 0.3 * macro);
	vec4 dirt = texture(dirt_tex, p / 6.0);
	vec4 rock = texture(rock_tex, p / 9.0);
	vec4 sand = texture(sand_tex, p / 8.0);

	vec4 w = COLOR;
	float wg = clamp(1.0 - w.r - w.g - w.b, 0.0, 1.0);
	// height blend: the taller texture wins at the borders, like pebbles poking through grass
	float a_g = wg + grass.a * 0.6;
	float a_d = w.r + dirt.a * 0.6;
	float a_r = w.g + rock.a * 0.6;
	float a_s = w.b + sand.a * 0.6;
	float m = max(max(a_g, a_d), max(a_r, a_s)) - 0.25;
	float b_g = max(a_g - m, 0.0);
	float b_d = max(a_d - m, 0.0);
	float b_r = max(a_r - m, 0.0);
	float b_s = max(a_s - m, 0.0);
	float tot = b_g + b_d + b_r + b_s + 1e-4;
	b_g /= tot; b_d /= tot; b_r /= tot; b_s /= tot;

	vec3 gcol = grass.rgb * grass_tint;
	// forest floor: darker, cooler grass
	gcol = mix(gcol, gcol * vec3(0.62, 0.72, 0.58), w.a);
	// large-scale tone change across meadows
	gcol *= 1.0 + macro * 0.28;
	vec3 c = gcol * b_g + dirt.rgb * b_d + rock.rgb * b_r + sand.rgb * b_s;
	// desert: sand drifts over the grass
	float drift = sand_cover * clamp(b_g + b_d * 0.3 + (macro - 0.5) * 0.6, 0.0, 1.0);
	c = mix(c, sand.rgb * vec3(1.05, 0.98, 0.9), drift);
	// winter: snow everywhere, thinner on trodden roads and steep rock
	float patch = texture(dirt_tex, p / 23.0).a;
	float lying = snow_cover * clamp(b_g + b_s + b_d * (0.45 + patch * 0.4) + b_r * 0.3 + (patch - 0.5) * 0.35, 0.0, 1.0);
	vec3 snow_col = mix(vec3(0.78, 0.83, 0.91), vec3(0.93, 0.95, 0.99), macro * 0.8 + patch * 0.2);
	c = mix(c, snow_col, lying);
	// snow on the high mountains
	float snow = max(smoothstep(9.0, 12.0, wpos.y + macro * 2.0), lying * 0.85);
	c = mix(c, vec3(0.92, 0.93, 0.95), smoothstep(9.0, 12.0, wpos.y + macro * 2.0));

	vec3 n_g = texture(grass_nrm, uv1).rgb;
	vec3 n_d = texture(dirt_nrm, p / 6.0).rgb;
	vec3 n_r = texture(rock_nrm, p / 9.0).rgb;
	NORMAL_MAP = normalize(n_g * b_g + n_d * b_d + n_r * b_r + vec3(0.5, 0.5, 1.0) * b_s);
	NORMAL_MAP_DEPTH = 1.0 - snow;

	float d_iran = 1e5;
	float d_turan = 1e5;
	for (int i = 0; i < 12; i++) {
		if (i >= zone_count) break;
		float d = length(p - vec2(zones[i * 4], zones[i * 4 + 1])) - zones[i * 4 + 2];
		if (zones[i * 4 + 3] < 0.5) d_iran = min(d_iran, d); else d_turan = min(d_turan, d);
	}
	float band_i = 1.0 - smoothstep(0.0, 0.45, abs(d_iran));
	float band_t = 1.0 - smoothstep(0.0, 0.45, abs(d_turan));
	if (d_iran < 0.0) c = mix(c, iran_color.rgb, 0.05);
	if (d_turan < 0.0) c = mix(c, turan_color.rgb, 0.05);
	c = mix(c, iran_color.rgb * 1.2, band_i * 0.75);
	c = mix(c, turan_color.rgb * 1.2, band_t * 0.75);

	if (grid_alpha > 0.0 && d_iran < 0.0) {
		vec2 gq = abs(fract(p / 2.0) - 0.5);
		float line = 1.0 - smoothstep(0.44, 0.49, max(gq.x, gq.y));
		c = mix(c, vec3(1.0, 0.95, 0.8), (1.0 - line) * grid_alpha);
	}
	if (ghost.w != 0.0) {
		vec2 q = abs(p - ghost.xy);
		if (max(q.x, q.y) < ghost.z) {
			c = mix(c, ghost.w > 0.0 ? vec3(0.35, 0.95, 0.45) : vec3(1.0, 0.25, 0.2), 0.5);
		}
	}
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.95, 0.8, b_r), 0.6, lying);
	SPECULAR = 0.25;
}
