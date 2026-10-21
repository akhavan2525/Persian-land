shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Leaf cards of the trees: cut out by the leaf texture, tinted per tree, swaying in the wind.
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.45;
uniform float wind = 0.06;
uniform vec3 leaf_tint = vec3(1.0);   // autumn gold, dry steppe, dark forest...
uniform float snow_amt = 0.0;         // winter: snow on the upper leaves
uniform float bare = 0.0;             // winter: share of leaves fallen (0 = full crown)
uniform vec3 dry_tint = vec3(0.78, 0.56, 0.34); // the few leaves left, dried brown

varying float tint_dark;
varying vec3 leaf_pos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.3 + wp.x * 0.35 + wp.z * 0.21) + 0.5 * sin(TIME * 2.7 + wp.z * 0.8);
	VERTEX.x += sway * wind * VERTEX.y * 0.25;
	VERTEX.z += sway * wind * VERTEX.y * 0.12;
	// leaves low and inside the crown get less sky light
	tint_dark = clamp(VERTEX.y / 6.0, 0.0, 1.0);
	leaf_pos = VERTEX + MODEL_MATRIX[3].xyz * 0.37;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	if (t.a < alpha_cut) {
		discard;
	}
	// winter: whole clumps of leaves fall, the rest dry up
	if (bare > 0.0 && hash3(floor(leaf_pos * 1.6)) < bare) {
		discard;
	}
	vec3 c = t.rgb * COLOR.rgb * leaf_tint * (0.85 + 0.35 * tint_dark);
	c = mix(c, dot(c, vec3(0.33)) * dry_tint * 1.6, clamp(bare * 1.2, 0.0, 1.0));
	float top = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	c = mix(c, vec3(0.9, 0.93, 0.98), snow_amt * (0.35 + 0.65 * tint_dark) * (0.6 + 0.4 * top));
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = 0.15;
	// light coming through the leaves from behind
	BACKLIGHT = c * 0.35;
}
