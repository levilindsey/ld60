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
	OPENING,
	IDLE,
	DRAGGING,
	SETTLING,
	CLOSING,
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
	%ClickArea.input_event.connect(_on_click_area_input_event)
	%CloseButton.input_event.connect(_on_close_button_input_event)


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
	_set_state(State.OPENING)
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


## Quickly turns every page back to the start, then closes the cover.
func close() -> void:
	if state != State.IDLE:
		return
	G.print("Closing instruction manual", ScaffolderLog.CATEGORY_INTERACTION)
	_set_state(State.CLOSING)
	_turn_back_to_first_spread()


func _on_cover_flipped() -> void:
	%Closed.visible = false
	%Leaf.set_contents(null, _get_page_content(0))
	%Leaf.visible = true
	_leaf_bend_direction = 1.0
	_set_leaf_progress(0.5)
	_tween_leaf_progress(0.5, 1.0, _on_left_page_unfolded)


func _on_left_page_unfolded() -> void:
	%LeftPage.visible = true
	_show_spread()
	_set_state(State.IDLE)
	opened.emit()


func _on_click_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_index: int,
) -> void:
	if not _is_left_mouse_event(event, true):
		return
	var x := _get_local_x(event)
	match state:
		State.CLOSED:
			if x >= 0.0:
				open()
		State.IDLE:
			_start_drag(x >= 0.0, x)


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
	_set_state(State.DRAGGING)


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
	_set_state(State.SETTLING)
	_tween_leaf_progress(
		_leaf_progress,
		target_progress,
		_on_leaf_settled.bind(is_completing),
	)


func _on_leaf_settled(is_completing: bool) -> void:
	if is_completing:
		spread_index += 1 if _is_turning_forward else -1
	_show_spread()
	_set_state(State.IDLE)
	if is_completing:
		page_flipped.emit(spread_index)


func _on_close_button_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_index: int,
) -> void:
	if _is_left_mouse_event(event, true):
		close()


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
	_set_state(State.CLOSED)
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


func _set_state(new_state: State) -> void:
	state = new_state
	%CloseButton.visible = new_state != State.CLOSED


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


func _is_left_mouse_event(event: InputEvent, is_pressed: bool) -> bool:
	# Touch input arrives as emulated mouse events.
	return (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed == is_pressed
	)
