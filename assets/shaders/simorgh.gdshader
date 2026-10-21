shader_type spatial;
render_mode cull_disabled;

// The Simorgh's painted feathers, with wings that beat from the shoulders.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float flap = 0.0;          // wing angle in radians, set by the script
uniform float shoulder = 0.18;     // half width of the body in model units
uniform float span = 0.95;         // distance from the centre to a wing tip
uniform float glow = 0.35;         // golden inner light

void vertex() {
	float ax = abs(VERTEX.x);
	float d = ax - shoulder;
	if (d > 0.0) {
		// the outer wing bends a little more than the inner wing, like a real wing beat
		float t = clamp(d / (span - shoulder), 0.0, 1.0);
		float ang = flap * (0.75 + 0.5 * t);
		float s = sign(VERTEX.x);
		VERTEX.x = s * (shoulder + d * cos(ang));
		VERTEX.z += d * sin(ang);
	}
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 0.7;
	EMISSION = c.rgb * glow;
}
