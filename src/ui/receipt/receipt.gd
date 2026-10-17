class_name Receipt
extends Control
## The receipt card that slides in when an item goes into the outbox. It lists
## the item's name, each kind of defect with its count and points, the time
## and the total. Then the stars pop in one at a time, and three stars add a
## sparkle.
##
## While it's open, its full-rect root stops every mouse press, so the first
## click only dismisses the card. It also goes away by itself after a few
## seconds. Put it in a CanvasLayer in the level. See docs/design/quality.md.


## The card has slid away and the receipt is done.
signal closed

const _SPARKLE_COUNT := 6
const _SPARKLE_SIZE_PX := 24.0
const _SPARKLE_OUTLINE_PX := 2.0
const _SPARKLE_RADIUS_PX := 56.0
const _SPARKLE_SEC := 0.6
const _SPARKLE_COLOR := Color(1.0, 0.92, 0.4)
## The scale a star pops in from.
const _STAR_POP_SCALE := 0.2
const _STAR_POP_SEC := 0.3
const _COST_COLOR := Color(0.7, 0.15, 0.1)
const _GOOD_COLOR := Color(0.12, 0.5, 0.2)

## How long the card takes to slide in or out.
@export var slide_sec := 0.35
## How far the card sits off the edge of the screen when it's away, in pixels.
@export var slide_distance_px := 520.0
## The time between the card arriving and the first star, and between one
## star and the next.
@export var star_interval_sec := 0.4
## How long after opening the card slides away by itself.
@export var auto_close_sec := 3.0

var _is_open := false
var _is_closing := false
var _can_close := false
var _tween: Tween
var _stars: Array[StarIcon] = []

@onready var _slide: Control = %Slide


func _ready() -> void:
	for child in %Stars.get_children():
		_stars.append(child as StarIcon)
	_set_closed()


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null:
		return
	var is_left_press := (
		mouse_event.pressed
		and mouse_event.button_index == MOUSE_BUTTON_LEFT
	)
	if is_left_press and _can_close:
		close()
	accept_event()


## Shows the card. A receipt that is still showing makes room for it.
func open(item_name: String, quality: RepairQuality) -> void:
	if _is_open:
		_kill_tween()
		_set_closed()
		closed.emit()

	_is_open = true
	_populate(item_name, quality)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_slide.position.x = slide_distance_px
	_play_sound(&"whoosh")

	var star_count := quality.get_stars()
	var star_phase_sec := star_count * star_interval_sec
	# The time to wait is counted from now, not from the end of the stars.
	var hold_sec := maxf(auto_close_sec - slide_sec - star_phase_sec, 0.0)

	# Pausing the game pauses the card, and its countdown with it.
	_tween = create_tween()
	_tween.tween_property(
		_slide,
		"position:x",
		0.0,
		slide_sec,
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_enable_closing)
	for index in star_count:
		_tween.tween_interval(star_interval_sec)
		_tween.tween_callback(_pop_star.bind(index, star_count))
	_tween.tween_interval(hold_sec)
	_tween.tween_callback(close)


## Slides the card away, then emits `closed`. Does nothing if the card isn't
## showing.
func close() -> void:
	if not _is_open or _is_closing:
		return
	_is_closing = true
	# Clicks go through to the world again while the card slides away.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_tween()
	_play_sound(&"whoosh")

	_tween = create_tween()
	_tween.tween_property(
		_slide,
		"position:x",
		slide_distance_px,
		slide_sec,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_on_slid_away)


func _populate(item_name: String, quality: RepairQuality) -> void:
	%NameLabel.text = item_name

	for row in %Lines.get_children():
		%Lines.remove_child(row)
		row.queue_free()

	var summary := quality.get_summary()
	if summary.is_empty():
		_add_row("No defects", "", _GOOD_COLOR)
	for line in summary:
		var defect_name := RepairQuality.get_defect_name(line.defect)
		if line.count > 1:
			defect_name += " x%d" % line.count
		_add_row(defect_name, "-%d" % line.points, _COST_COLOR)

	var time_text := "Time %s" % _format_time(quality.repair_time_sec)
	if quality.par_time_sec > 0.0:
		time_text += " (par %s)" % _format_time(quality.par_time_sec)
	var time_penalty := quality.get_time_penalty()
	if time_penalty > 0:
		_add_row(time_text, "-%d" % time_penalty, _COST_COLOR)
	else:
		_add_row(time_text, "", _GOOD_COLOR)

	%TotalLabel.text = str(quality.get_score())

	for star in _stars:
		star.is_lit = false
		star.scale = Vector2.ONE


func _add_row(
	left_text: String,
	right_text: String,
	right_color: Color,
) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var left := Label.new()
	left.text = left_text
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)

	var right := Label.new()
	right.text = right_text
	right.add_theme_color_override(&"font_color", right_color)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	%Lines.add_child(row)


func _enable_closing() -> void:
	_can_close = true


func _pop_star(index: int, star_count: int) -> void:
	var star := _stars[index]
	star.is_lit = true
	_play_sound(&"ding", true)

	star.scale = Vector2.ONE * _STAR_POP_SCALE
	star.create_tween().tween_property(
		star,
		"scale",
		Vector2.ONE,
		_STAR_POP_SEC,
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Three stars earn a sparkle on the last one.
	var is_last_of_all := (
		star_count == RepairQuality.MAXIMUM_STARS
		and index == star_count - 1
	)
	if is_last_of_all:
		_sparkle(star)


func _sparkle(star: StarIcon) -> void:
	var center := (star.size - Vector2.ONE * _SPARKLE_SIZE_PX) / 2.0
	for index in _SPARKLE_COUNT:
		var sparkle := StarIcon.new()
		sparkle.point_count = 4
		sparkle.inner_ratio = 0.2
		sparkle.is_lit = true
		sparkle.lit_color = _SPARKLE_COLOR
		sparkle.outline_width = _SPARKLE_OUTLINE_PX
		sparkle.size = Vector2.ONE * _SPARKLE_SIZE_PX
		sparkle.position = center
		sparkle.scale = Vector2.ZERO
		star.add_child(sparkle)

		var direction := Vector2.from_angle(TAU * index / _SPARKLE_COUNT)
		var tween := sparkle.create_tween()
		tween.tween_method(
			_update_sparkle.bind(sparkle, center, direction),
			0.0,
			1.0,
			_SPARKLE_SEC,
		)
		tween.tween_callback(sparkle.queue_free)


## Flies a sparkle out from the star, growing and then shrinking as it spins.
func _update_sparkle(
	progress: float,
	sparkle: StarIcon,
	center: Vector2,
	direction: Vector2,
) -> void:
	var distance := _SPARKLE_RADIUS_PX * ease(progress, 0.4)
	sparkle.position = center + direction * distance
	sparkle.scale = Vector2.ONE * sin(progress * PI)
	sparkle.rotation = progress * PI / 2.0


func _on_slid_away() -> void:
	_set_closed()
	closed.emit()


## The state of a receipt that isn't showing.
func _set_closed() -> void:
	_is_open = false
	_is_closing = false
	_can_close = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _kill_tween() -> void:
	if is_instance_valid(_tween):
		_tween.kill()


func _play_sound(sound_name: StringName, force_restart := false) -> void:
	if is_instance_valid(G.audio):
		G.audio.play_sound(sound_name, force_restart)


static func _format_time(seconds: float) -> String:
	return Utils.get_time_string_from_seconds(seconds, false, false, true)
