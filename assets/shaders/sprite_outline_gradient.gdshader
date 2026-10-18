shader_type canvas_item;

// Gradient outline: like sprite_outline.gdshader, but the outline band
// fades across its depth. The texel touching the sprite (inner edge,
// depth 0) is outline_color_inner; the far edge of the band (depth 1)
// is outline_color_outer. Set the outer alpha to 0 (the default) for a
// glow that fades out, or give it a second opaque color for a
// two-color rim.
//
// The width is in world pixels, not texels, so the band is the same
// size on screen no matter how the sprite is scaled. A big texture
// shown small (a screw head, say) still gets a full-width rim.

uniform vec4 outline_color_inner : source_color = vec4(1.0, 0.92, 0.4, 1.0);
uniform vec4 outline_color_outer : source_color = vec4(1.0, 0.92, 0.4, 0.0);
/// Band width in world pixels, at any sprite scale.
uniform float outline_width_px : hint_range(0.0, 32.0, 0.5) = 8.0;
/// Shapes the fade across the band: 1.0 is linear, above 1.0 stays
/// near the inner color longer then drops off, below 1.0 fades early.
uniform float gradient_power : hint_range(0.25, 4.0, 0.05) = 1.0;
/// Pulse cycles per second: the outline breathes between 75% and
/// full strength. 0.0 keeps it steady.
uniform float pulse_speed : hint_range(0.0, 4.0, 0.1) = 0.9;
uniform bool outline_enabled = true;

/// World pixels covered by one texture texel, per axis. A sprite
/// local unit is one texel, so this is the model matrix's scale.
varying vec2 texel_world_size;

void vertex() {
	texel_world_size = vec2(
		max(
			length((MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy),
			0.0001
		),
		max(
			length((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy),
			0.0001
		)
	);
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec4 result = color;

	if (outline_enabled && color.a < 0.5 && outline_width_px > 0.0) {
		vec2 texture_size = vec2(textureSize(TEXTURE, 0));
		vec2 pixel_size = 1.0 / texture_size;

		// Probe outwards in world-pixel steps, at most 16 of them, so
		// a heavily downscaled sprite does not need hundreds of texel
		// steps to cross the band. The nearest opaque probe is this
		// texel's depth into the outline, in world pixels.
		float step_world = max(
			min(texel_world_size.x, texel_world_size.y),
			outline_width_px / 16.0
		);
		const int MAX_STEPS = 16;
		const float NO_HIT = 1e6;
		float nearest_dist = NO_HIT;
		for (int dx = -MAX_STEPS; dx <= MAX_STEPS; dx++) {
			for (int dy = -MAX_STEPS; dy <= MAX_STEPS; dy++) {
				if (dx == 0 && dy == 0) {
					continue;
				}
				vec2 offset_world = (
					vec2(float(dx), float(dy)) * step_world
				);
				float dist = length(offset_world);
				if (dist > outline_width_px || dist >= nearest_dist) {
					continue;
				}
				vec2 sample_uv = (
					UV + offset_world / texel_world_size * pixel_size
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
			// The first probe ring out is depth 0; the far edge is 1.
			float depth = clamp(
				(nearest_dist - step_world)
				/ max(outline_width_px - step_world, 0.001),
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
				result.a *= mix(0.75, 1.0, wave);
			}
		}
	}

	COLOR = result;
}
