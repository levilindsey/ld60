shader_type canvas_item;

// Gradient outline: like sprite_outline.gdshader, but the outline band
// fades across its depth. The texel touching the sprite (inner edge,
// depth 0) is outline_color_inner; the far edge of the band (depth 1)
// is outline_color_outer. Set the outer alpha to 0 (the default) for a
// glow that fades out, or give it a second opaque color for a
// two-color rim.

uniform vec4 outline_color_inner : source_color = vec4(1.0, 0.92, 0.4, 1.0);
uniform vec4 outline_color_outer : source_color = vec4(1.0, 0.92, 0.4, 0.0);
uniform float outline_width : hint_range(0.0, 16.0, 0.5) = 8.0;
/// Shapes the fade across the band: 1.0 is linear, above 1.0 stays
/// near the inner color longer then drops off, below 1.0 fades early.
uniform float gradient_power : hint_range(0.25, 4.0, 0.05) = 1.0;
/// Pulse cycles per second: the outline breathes between 65% and
/// full strength. 0.0 keeps it steady.
uniform float pulse_speed : hint_range(0.0, 4.0, 0.1) = 0.9;
uniform bool outline_enabled = true;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec4 result = color;

	if (outline_enabled && color.a < 0.5 && outline_width > 0.0) {
		vec2 texture_size = vec2(textureSize(TEXTURE, 0));
		vec2 pixel_size = 1.0 / texture_size;
		int radius = int(ceil(outline_width));

		// Find the nearest opaque texel within the band. Its distance
		// is this texel's depth into the outline.
		const int MAX_RADIUS = 16;
		const float NO_HIT = 1e6;
		float nearest_dist = NO_HIT;
		for (int dx = -MAX_RADIUS; dx <= MAX_RADIUS; dx++) {
			if (abs(dx) > radius) {
				continue;
			}
			for (int dy = -MAX_RADIUS; dy <= MAX_RADIUS; dy++) {
				if (abs(dy) > radius || (dx == 0 && dy == 0)) {
					continue;
				}
				float dist = length(vec2(float(dx), float(dy)));
				if (dist > outline_width || dist >= nearest_dist) {
					continue;
				}
				vec2 sample_uv = (
					UV + vec2(float(dx), float(dy)) * pixel_size
				);
				if (
					sample_uv.x < 0.0 || sample_uv.x > 1.0
					|| sample_uv.y < 0.0 || sample_uv.y > 1.0
				) {
					continue;
				}
				if (texture(TEXTURE, sample_uv).a >= 0.5) {
					nearest_dist = dist;
				}
			}
		}

		if (nearest_dist != NO_HIT) {
			// Adjacent texel (dist 1) is depth 0; the far edge is 1.
			float depth = clamp(
				(nearest_dist - 1.0) / max(outline_width - 1.0, 1.0),
				0.0,
				1.0
			);
			result = mix(
				outline_color_inner,
				outline_color_outer,
				pow(depth, gradient_power)
			);
			if (pulse_speed > 0.0) {
				float wave = (
					0.5 + 0.5 * sin(TIME * 6.2831853 * pulse_speed)
				);
				result.a *= mix(0.65, 1.0, wave);
			}
		}
	}

	COLOR = result;
}
