shader_type canvas_item;

// Draws a sprite onto an arbitrary four-cornered shape with
// perspective-correct texture mapping, so the texture doesn't kink along
// the quad's diagonal. Corners are in the sprite's local space.

uniform vec2 top_left = vec2(-0.5, -0.5);
uniform vec2 top_right = vec2(0.5, -0.5);
uniform vec2 bottom_right = vec2(0.5, 0.5);
uniform vec2 bottom_left = vec2(-0.5, 0.5);

varying vec3 projective_uv;
varying vec4 vertex_color;


vec2 intersect_lines(vec2 a_start, vec2 a_end, vec2 b_start, vec2 b_end) {
	vec2 a_direction = a_end - a_start;
	vec2 b_direction = b_end - b_start;
	float denominator = (
		a_direction.x * b_direction.y - a_direction.y * b_direction.x
	);
	float t = (
		(b_start.x - a_start.x) * b_direction.y
		- (b_start.y - a_start.y) * b_direction.x
	) / denominator;
	return a_start + a_direction * t;
}


void vertex() {
	bool is_left = UV.x < 0.5;
	bool is_top = UV.y < 0.5;
	vec2 corner;
	vec2 opposite;
	if (is_top) {
		corner = is_left ? top_left : top_right;
		opposite = is_left ? bottom_right : bottom_left;
	} else {
		corner = is_left ? bottom_left : bottom_right;
		opposite = is_left ? top_right : top_left;
	}

	// Each corner's depth weight comes from how far it sits from where the
	// diagonals cross, relative to the opposite corner.
	vec2 center = intersect_lines(
		top_left,
		bottom_right,
		top_right,
		bottom_left
	);
	float corner_distance = distance(corner, center);
	float opposite_distance = distance(opposite, center);
	float q = (corner_distance + opposite_distance) / opposite_distance;

	VERTEX = corner;
	projective_uv = vec3(UV * q, q);
	vertex_color = COLOR;
}


void fragment() {
	COLOR = (
		texture(TEXTURE, projective_uv.xy / projective_uv.z) * vertex_color
	);
}
