extends Control
## Pen scribbles over words the customer crossed out on the ticket. A
## child of the complaint Label, covering it. `ranges` holds the crossed
## out character ranges of the Label's text, each `Vector2i(start, end)`.


## Ink to match the handwriting.
const _INK := Color(0.22, 0.15, 0.08, 1.0)
const _STROKE_WIDTH := 2.5
## The pen's zigzag: how far apart its turns are, in pixels.
const _ZIG_STEP_PX := 5.0
## Overlapping passes of the pen over each word.
const _PASS_COUNT := 3
## Share of the glyph height the scribble covers, centered.
const _HEIGHT_SHARE := 0.85


var ranges: Array[Vector2i] = []:
	set(value):
		ranges = value
		queue_redraw()


func _draw() -> void:
	var label := get_parent() as Label
	var random := RandomNumberGenerator.new()
	for range_index in ranges.size():
		# The same seed each draw, so the scribble holds still.
		random.seed = range_index + 1
		for rect in _get_line_rects(label, ranges[range_index]):
			for _pass in _PASS_COUNT:
				_draw_zigzag(rect, random)


## The crossed out range's bounds, one rect for each line it wraps onto.
func _get_line_rects(label: Label, char_range: Vector2i) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for index in range(char_range.x, char_range.y):
		var bounds := label.get_character_bounds(index)
		if bounds.size.x <= 0.0:
			continue
		if (
			not rects.is_empty()
			and is_equal_approx(rects.back().position.y, bounds.position.y)
		):
			rects[rects.size() - 1] = rects.back().merge(bounds)
		else:
			rects.append(bounds)
	return rects


func _draw_zigzag(rect: Rect2, random: RandomNumberGenerator) -> void:
	var height := rect.size.y * _HEIGHT_SHARE
	var top := rect.position.y + (rect.size.y - height) / 2.0
	var points := PackedVector2Array()
	var x := rect.position.x - random.randf_range(0.0, 3.0)
	var is_top := random.randf() < 0.5
	while x < rect.end.x + 3.0:
		var y := top + (0.0 if is_top else height)
		points.append(Vector2(
			x + random.randf_range(-1.5, 1.5),
			y + random.randf_range(-3.0, 3.0),
		))
		is_top = not is_top
		x += _ZIG_STEP_PX * random.randf_range(0.7, 1.3)
	if points.size() >= 2:
		draw_polyline(points, _INK, _STROKE_WIDTH, true)
