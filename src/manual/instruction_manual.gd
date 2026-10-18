class_name InstructionManual
extends Node2D
## An in-world instruction manual. Starts closed; tapping the cover flips it
## open. Once open, pages turn by swiping (or tapping) a page.
##
## Page turns use a single bending ManualLeaf hinged at the spine. Leaf
## progress 0 means the leaf lies over the right page; 1 means it lies over
## the left page.


signal opened
signal closed
signal page_flipped(spread_index: int)


enum State {
	CLOSED,
	LIFTING,
	OPENING,
	IDLE,
	DRAGGING,
	SETTLING,
	CLOSING,
	LOWERING,
}


const _PAGE_WIDTH := 240.0
const _COVER_FLIP_DURATION_SEC := 0.2
## Duration of the move between the desk and the open pose.
const _LIFT_DURATION_SEC := 0.3
## Duration of a full leaf turn. Partial turns take proportionally less.
const _FULL_TURN_DURATION_SEC := 0.4
const _MIN_TURN_DURATION_SEC := 0.02
## Duration of each fast page turn while closing.
const _CLOSING_TURN_DURATION_SEC := 0.12
const _CLOSE_BUTTON_POP_DURATION_SEC := 0.3
## How far the close button overshoots its size as it pops in.
const _CLOSE_BUTTON_OVERSHOOT := 1.7
## How far the close button is spun while fully shrunk.
const _CLOSE_BUTTON_SPIN_RADIANS := -PI
## Releases that moved less than this count as taps.
const _TAP_MAX_DISTANCE_PX := 8.0
## Release speed in the turn direction that completes a turn early.
const _FLING_SPEED_PX_PER_SEC := 600.0


## Content for each inner page, in reading order. Each spread shows two
## pages: even indices on the left, odd indices on the right.
@export var page_contents: Array[Texture2D] = []
## How far each page (and the cover) slides toward the spine, so the page
## outlines overlap there instead of leaving a gap.
@export var spine_overlap := 4.0
## Where the closed manual rests. Its position, rotation, scale and skew
## lay the closed book flat on the desk. The manual lifts from here to its
## own placement in the level to open. Without one, the manual stays put.
@export var desk_spot: Node2D
## The closed cover's corners while resting on the desk, for a perspective
## view of the book lying flat: top left, top right, bottom right, bottom
## left. In the cover sprite's local space, where the unwarped cover spans
## ±120 by ±160. They ease back to the flat cover as the manual lifts.
@export var desk_cover_corners := PackedVector2Array()


var state := State.CLOSED
var spread_index := 0


var _is_turning_forward := true
var _leaf_progress := 0.0
var _leaf_bend_direction := 1.0
var _drag_start_x := 0.0
var _drag_start_progress := 0.0
var _drag_velocity_x := 0.0
var _open_position := Vector2.ZERO
var _open_rotation := 0.0
var _open_scale := Vector2.ONE
var _open_skew := 0.0
var _cover_corners := PackedVector2Array()


func _ready() -> void:
	%LeftPage.position.x = -_PAGE_WIDTH / 2.0 + spine_overlap
	%RightPage.position.x = _PAGE_WIDTH / 2.0 - spine_overlap
	%Closed.position.x = -spine_overlap
	%Leaf.spine_overlap = spine_overlap
	_show_spread()
	_open_position = global_position
	_open_rotation = global_rotation
	_open_scale = global_scale
	_open_skew = global_skew
	_set_cover_corners(_get_flat_cover_corners())
	if is_instance_valid(desk_spot):
		_set_lift(0.0)
		reset_physics_interpolation()


func _input(event: InputEvent) -> void:
	if state != State.DRAGGING:
		return
	if event is InputEventMouseMotion:
		_drag_velocity_x = event.velocity.x
		_set_leaf_progress(_get_drag_progress(_get_local_x(event)))
	elif _is_left_mouse_event(event, false):
		_release_drag(_get_local_x(event))


# Presses are routed here rather than through Area2D picking, so the
# manual sees them before the level's Hand and can keep them from
# reaching items behind it.
func _unhandled_input(event: InputEvent) -> void:
	if not _is_left_mouse_event(event, true):
		return
	if _handle_press(event as InputEventMouseButton):
		get_viewport().set_input_as_handled()


func open() -> void:
	if state != State.CLOSED:
		return
	G.print("Opening instruction manual", ScaffolderLog.CATEGORY_INTERACTION)
	_play_sound(&"page_flip")
	state = State.LIFTING
	_tween_lift(0.0, 1.0, _on_lifted)


## Quickly turns every page back to the start, then closes the cover.
func close() -> void:
	if state != State.IDLE:
		return
	G.print("Closing instruction manual", ScaffolderLog.CATEGORY_INTERACTION)
	_play_sound(&"pages_flip")
	state = State.CLOSING
	_pop_out_close_button()
	_turn_back_to_first_spread()


func _on_lifted() -> void:
	state = State.OPENING
	%RightPage.visible = true
	_pop_in_close_button()
	G.time.tween_property(
		%Closed,
		"scale:x",
		1.0,
		0.0,
		_COVER_FLIP_DURATION_SEC,
		"ease_in",
		0.0,
		TimeType.APP_PHYSICS,
		_on_cover_flipped,
	)


func _on_cover_flipped() -> void:
	%Closed.visible = false
	%Spine.visible = true
	%Leaf.set_contents(null, _get_page_content(0))
	%Leaf.visible = true
	_leaf_bend_direction = 1.0
	_set_leaf_progress(0.5)
	_tween_leaf_progress(0.5, 1.0, _on_left_page_unfolded)


func _on_left_page_unfolded() -> void:
	%LeftPage.visible = true
	_show_spread()
	state = State.IDLE
	opened.emit()


## Returns whether the press landed on the manual.
func _handle_press(event: InputEventMouseButton) -> bool:
	if %CloseButton.visible and _is_on_shape(%CloseButtonShape, event):
		close()
		return true
	match state:
		State.CLOSED:
			var cover_point := (
				(%Cover.make_input_local(event) as InputEventMouse).position
			)
			if not Geometry2D.is_point_in_polygon(cover_point, _cover_corners):
				return false
			open()
			return true
		State.IDLE:
			if not _is_on_shape(%ClickAreaShape, event):
				return false
			var x := _get_local_x(event)
			_start_drag(x >= 0.0, x)
			return true
		_:
			# Mid-animation, the book still blocks presses on what's
			# behind it.
			return _is_on_shape(%ClickAreaShape, event)


func _start_drag(is_forward: bool, x: float) -> void:
	if is_forward and not _has_next_spread():
		return
	if not is_forward and spread_index == 0:
		return
	_is_turning_forward = is_forward
	_drag_start_x = x
	_drag_start_progress = 0.0 if is_forward else 1.0
	_drag_velocity_x = 0.0
	# The free edge trails behind the turn.
	_leaf_bend_direction = -1.0 if is_forward else 1.0
	_prepare_leaf(spread_index if is_forward else spread_index - 1)
	_set_leaf_progress(_drag_start_progress)
	state = State.DRAGGING


func _release_drag(x: float) -> void:
	var drag_distance := absf(x - _drag_start_x)
	var turn_fraction := (
		_leaf_progress if _is_turning_forward else 1.0 - _leaf_progress
	)
	# Positive when moving in the turn direction.
	var turn_speed := (
		-_drag_velocity_x if _is_turning_forward else _drag_velocity_x
	)
	var is_completing := (
		drag_distance < _TAP_MAX_DISTANCE_PX
		or turn_speed > _FLING_SPEED_PX_PER_SEC
		or (turn_speed > -_FLING_SPEED_PX_PER_SEC and turn_fraction > 0.5)
	)
	var target_progress := _drag_start_progress
	if is_completing:
		target_progress = 1.0 if _is_turning_forward else 0.0
		_play_sound(&"page_flip", true)
	state = State.SETTLING
	_tween_leaf_progress(
		_leaf_progress,
		target_progress,
		_on_leaf_settled.bind(is_completing),
	)


func _on_leaf_settled(is_completing: bool) -> void:
	if is_completing:
		spread_index += 1 if _is_turning_forward else -1
	_show_spread()
	state = State.IDLE
	if is_completing:
		page_flipped.emit(spread_index)


func _turn_back_to_first_spread() -> void:
	if spread_index == 0:
		_fold_first_page()
		return
	_leaf_bend_direction = 1.0
	_prepare_leaf(spread_index - 1)
	_set_leaf_progress(1.0)
	_tween_leaf_progress(
		1.0,
		0.0,
		_on_closing_turn_finished,
		_CLOSING_TURN_DURATION_SEC,
	)


func _on_closing_turn_finished() -> void:
	spread_index -= 1
	_show_spread()
	_turn_back_to_first_spread()


## Reverse of the opening unfold: the first left page folds back into the
## spine.
func _fold_first_page() -> void:
	%LeftPage.visible = false
	%Leaf.set_contents(null, _get_page_content(0))
	%Leaf.visible = true
	_leaf_bend_direction = 1.0
	_set_leaf_progress(1.0)
	_tween_leaf_progress(
		1.0,
		0.5,
		_on_first_page_folded,
		_CLOSING_TURN_DURATION_SEC,
	)


func _on_first_page_folded() -> void:
	%Leaf.visible = false
	%Spine.visible = false
	%Closed.visible = true
	%Closed.reset_physics_interpolation()
	G.time.tween_property(
		%Closed,
		"scale:x",
		0.0,
		1.0,
		_COVER_FLIP_DURATION_SEC,
		"ease_out",
		0.0,
		TimeType.APP_PHYSICS,
		_on_cover_closed,
	)


func _on_cover_closed() -> void:
	state = State.LOWERING
	%RightPage.visible = false
	_tween_lift(1.0, 0.0, _on_lowered)


func _on_lowered() -> void:
	state = State.CLOSED
	closed.emit()


func _tween_lift(
	from_lift: float,
	to_lift: float,
	on_completed: Callable,
) -> void:
	if not is_instance_valid(desk_spot):
		on_completed.call()
		return
	G.time.tween_method(
		self,
		"_set_lift",
		from_lift,
		to_lift,
		_LIFT_DURATION_SEC,
		"ease_in_out",
		0.0,
		TimeType.APP_PHYSICS,
		on_completed,
	)


## 0 rests at `desk_spot`; 1 is the open pose where the level placed the
## manual.
func _set_lift(lift: float) -> void:
	global_position = desk_spot.global_position.lerp(_open_position, lift)
	global_rotation = lerp_angle(
		desk_spot.global_rotation,
		_open_rotation,
		lift,
	)
	global_scale = desk_spot.global_scale.lerp(_open_scale, lift)
	global_skew = lerpf(desk_spot.global_skew, _open_skew, lift)

	var flat_corners := _get_flat_cover_corners()
	if desk_cover_corners.size() != flat_corners.size():
		_set_cover_corners(flat_corners)
		return
	var corners := PackedVector2Array()
	for i in flat_corners.size():
		corners.append(desk_cover_corners[i].lerp(flat_corners[i], lift))
	_set_cover_corners(corners)


## The cover's corners when it isn't warped: top left, top right, bottom
## right, bottom left, in the cover sprite's local space.
func _get_flat_cover_corners() -> PackedVector2Array:
	var half_size: Vector2 = %Cover.texture.get_size() / 2.0
	return PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
	])


func _set_cover_corners(corners: PackedVector2Array) -> void:
	_cover_corners = corners
	var material: ShaderMaterial = %Cover.material
	material.set_shader_parameter("top_left", corners[0])
	material.set_shader_parameter("top_right", corners[1])
	material.set_shader_parameter("bottom_right", corners[2])
	material.set_shader_parameter("bottom_left", corners[3])


func _play_sound(sound_name: StringName, force_restart := false) -> void:
	# The manual can be run on its own, before AudioMain exists.
	if is_instance_valid(G.audio):
		G.audio.play_sound(sound_name, force_restart)


func _get_drag_progress(x: float) -> float:
	var drag_x := _drag_start_x - x
	return clampf(
		_drag_start_progress + drag_x / (2.0 * _PAGE_WIDTH),
		0.0,
		1.0,
	)


func _tween_leaf_progress(
	from_progress: float,
	to_progress: float,
	on_completed: Callable,
	full_turn_duration_sec := _FULL_TURN_DURATION_SEC,
) -> void:
	var duration := maxf(
		absf(to_progress - from_progress) * full_turn_duration_sec,
		_MIN_TURN_DURATION_SEC,
	)
	G.time.tween_method(
		self,
		"_set_leaf_progress",
		from_progress,
		to_progress,
		duration,
		"ease_out",
		0.0,
		TimeType.APP_PHYSICS,
		on_completed,
	)


func _set_leaf_progress(progress: float) -> void:
	_leaf_progress = progress
	%Leaf.set_progress(progress, _leaf_bend_direction)


## Sets up the pages for a turn between `lower_spread` and the spread after
## it. The pages under the leaf show the destination, and the leaf's faces
## show the page being turned.
func _prepare_leaf(lower_spread: int) -> void:
	var upper_spread := lower_spread + 1
	%LeftPage.set_content(_get_page_content(lower_spread * 2))
	%RightPage.set_content(_get_page_content(upper_spread * 2 + 1))
	%Leaf.set_contents(
		_get_page_content(lower_spread * 2 + 1),
		_get_page_content(upper_spread * 2),
	)
	%Leaf.visible = true


func _pop_in_close_button() -> void:
	%CloseButton.visible = true
	_set_close_button_appearance(0.0)
	%CloseButtonSprite.reset_physics_interpolation()
	_tween_close_button_appearance(
		0.0,
		1.0,
		_set_close_button_appearance.bind(1.0),
	)


func _pop_out_close_button() -> void:
	_tween_close_button_appearance(1.0, 0.0, _on_close_button_popped_out)


func _on_close_button_popped_out() -> void:
	%CloseButton.visible = false


func _tween_close_button_appearance(
	from_appearance: float,
	to_appearance: float,
	on_completed: Callable,
) -> void:
	G.time.tween_method(
		self,
		"_set_close_button_appearance",
		from_appearance,
		to_appearance,
		_CLOSE_BUTTON_POP_DURATION_SEC,
		"linear",
		0.0,
		TimeType.APP_PHYSICS,
		on_completed,
	)


## 0 is fully shrunk and spun away; 1 is at rest. Scale follows a "back"
## curve, so it overshoots slightly on the way in and winds up slightly
## before shrinking on the way out.
func _set_close_button_appearance(appearance: float) -> void:
	var t := appearance - 1.0
	var back_scale := (
		1.0
		+ (_CLOSE_BUTTON_OVERSHOOT + 1.0) * t * t * t
		+ _CLOSE_BUTTON_OVERSHOOT * t * t
	)
	%CloseButtonSprite.scale = Vector2.ONE * maxf(back_scale, 0.0)
	%CloseButtonSprite.rotation = _CLOSE_BUTTON_SPIN_RADIANS * t * t


func _show_spread() -> void:
	%LeftPage.set_content(_get_page_content(spread_index * 2))
	%RightPage.set_content(_get_page_content(spread_index * 2 + 1))
	%Leaf.visible = false


func _has_next_spread() -> bool:
	return (spread_index + 1) * 2 < page_contents.size()


func _get_page_content(page_index: int) -> Texture2D:
	if page_index < page_contents.size():
		return page_contents[page_index]
	return null


func _is_on_shape(
	shape_node: CollisionShape2D,
	event: InputEventMouse,
) -> bool:
	var point := (shape_node.make_input_local(event) as InputEventMouse).position
	var size := (shape_node.shape as RectangleShape2D).size
	return Rect2(-size / 2.0, size).has_point(point)


func _get_local_x(event: InputEventMouse) -> float:
	return (make_input_local(event) as InputEventMouse).position.x


func _is_left_mouse_event(event: InputEvent, is_pressed: bool) -> bool:
	# Touch input arrives as emulated mouse events.
	return (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed == is_pressed
	)
