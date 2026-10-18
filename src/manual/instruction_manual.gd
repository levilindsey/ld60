class_name InstructionManual
extends LiftableProp
## An in-world instruction manual. Starts closed on the desk; tapping the
## cover lifts it and flips it open. Once open, pages turn by swiping (or
## tapping) a page, and a tap anywhere outside the book closes it.
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
## Duration of a full leaf turn. Partial turns take proportionally less.
const _FULL_TURN_DURATION_SEC := 0.4
const _MIN_TURN_DURATION_SEC := 0.02
## Duration of each fast page turn while closing.
const _CLOSING_TURN_DURATION_SEC := 0.12
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


var state := State.CLOSED
var spread_index := 0


var _is_turning_forward := true
var _leaf_progress := 0.0
var _leaf_bend_direction := 1.0
var _drag_start_x := 0.0
var _drag_start_progress := 0.0
var _drag_velocity_x := 0.0


func _ready() -> void:
	%LeftPage.position.x = -_PAGE_WIDTH / 2.0 + spine_overlap
	%RightPage.position.x = _PAGE_WIDTH / 2.0 - spine_overlap
	%Closed.position.x = -spine_overlap
	%Leaf.spine_overlap = spine_overlap
	_show_spread()
	super()


func _input(event: InputEvent) -> void:
	if state != State.DRAGGING:
		return
	if event is InputEventMouseMotion:
		_drag_velocity_x = event.velocity.x
		_set_leaf_progress(_get_drag_progress(_get_local_x(event)))
	elif _is_left_mouse_event(event, false):
		_release_drag(_get_local_x(event))


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
	close_button.pop_out()
	_turn_back_to_first_spread()


func _on_lifted() -> void:
	state = State.OPENING
	%RightPage.visible = true
	close_button.pop_in()
	G.time.tween_property(
		%Closed,
		"scale:x",
		1.0,
		0.0,
		_COVER_FLIP_DURATION_SEC,
		"ease_in_out",
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


func _handle_press(event: InputEventMouseButton) -> bool:
	if close_button.is_pressed_by(event):
		close()
		return true
	match state:
		State.CLOSED:
			if not _is_on_warped_sprite(event):
				return false
			open()
			return true
		State.IDLE:
			if not _is_on_shape(%ClickAreaShape, event):
				# Open and tapped outside: close the book. The tap is
				# spent, so it doesn't also press the bench behind.
				close()
				return true
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
		"ease_in_out",
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


func _get_local_x(event: InputEventMouse) -> float:
	return (make_input_local(event) as InputEventMouse).position.x
