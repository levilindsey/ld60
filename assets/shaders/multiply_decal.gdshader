shader_type canvas_item;
render_mode blend_mul;

// Multiply blending that respects the texture's alpha. The plain
// CanvasItemMaterial multiply mode multiplies the background by
// the sprite's color on every pixel of the quad, including the
// fully transparent ones, so white-on-transparent art (its color
// is white everywhere, with the pattern carried in alpha) paints
// a solid tinted rectangle. Here a transparent pixel outputs
// white, which leaves the background unchanged under a multiply,
// and a drawn pixel outputs its color weighted by its alpha.

varying vec4 modulate_color;

void vertex() {
	modulate_color = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float strength = tex.a * modulate_color.a;
	vec3 factor = tex.rgb * modulate_color.rgb;
	COLOR = vec4(mix(vec3(1.0), factor, strength), 1.0);
}
