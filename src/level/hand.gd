class_name Hand
extends Node2D
## The player's hand. It owns what is held, the cursor and where a
## left-button press goes (docs/design/tools.md "The hand").
##
## One `_unhandled_input` takes left presses and releases for the whole
## bench and ignores the other buttons. It marks an event handled only
## when it used it, so the booklet still gets its presses by physics
## picking.


const _QUERY_MAX_RESULTS := 32
const _NOPE_ICON_OFFSET := Vector2(14.0, -14.0)
## Frames the pointer's speed must stay past the throw
## threshold before a release counts as a throw. A single
## jump of the pointer never counts.
const _THROW_SUSTAIN_FRAMES := 3
## The device of the motion event that Input makes up when the cursor
## shape changes. Godot calls it InputEvent::DEVICE_ID_INTERNAL but
## doesn't expose it to scripts.
const _DEVICE_ID_INTERNAL := -2

## The tool, part or item in the hand, or null.
var held: Node2D
## A running microgame, or null. While set, it gets every press, drag
## and release through `on_pointer_pressed(global_position)`,
## `on_pointer_moved(global_position)` and
## `on_pointer_released(global_position)`.
var input_owner: Object
## The pointer in viewport pixels, from the latest mouse event.
var pointer_screen_position := Vector2.ZERO
## True when the latest press or motion came from a touch screen.
var is_touch := false
## The mouse mode the hand last applied.
var mouse_mode := Input.MOUSE_MODE_VISIBLE
## The cursor shape the hand last applied.
var cursor_shape := Input.CURSOR_ARROW

## The pointer in world space. The camera shakes, so this converts with
## the current canvas transform every time it is read.
var pointer_position: Vector2:
	get:
		return (
			get_canvas_transform().affine_inverse()
			* pointer_screen_position
		)

var _is_press_used := false
var _nope_tween: Tween
## Where a dragged item's origin sits relative to the pointer, so the item
## doesn't jump when it is grabbed.
var _drag_offset := Vector2.ZERO
## The turn of the dragged item, in radians. It follows the drag speed.
var _drag_tilt := 0.0
var _drag_previous_pointer := Vector2.ZERO
## A loose bench piece being dragged: a resting screw, a layer off
## its item or a part out of a drawer. Only one loose drag runs at
## a time.
var _loose_screw: Screw
var _loose_layer: RepairLayer
var _loose_part: Part
var _loose_drag_offset := Vector2.ZERO
## The pointer's speed, smoothed over the last frames of
## a drag, and how many frames it has stayed fast. A fast
## enough release throws the piece with this speed.
var _drag_velocity := Vector2.ZERO
var _throw_pointer_previous := Vector2.ZERO
var _has_throw_pointer_previous := false
var _drag_sustain_frames := 0


func _ready() -> void:
	pointer_screen_position = get_viewport().get_mouse_position()
	%NopeIcon.visible = false
	_update_cursor()


func _exit_tree() -> void:
	# The level is going away: a restart, or back to the title (LX2).
	_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_ARROW)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PAUSED:
			# The release may come while the tree is paused, and nothing
			# would see it. A dragged item goes back to the bench.
			if held is Repairable:
				var item := held as Repairable
				release()
				G.level.return_item(item)
			# The pause and credits overlays need a cursor.
			_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_ARROW)
		NOTIFICATION_UNPAUSED:
			_update_cursor()


func _physics_process(delta: float) -> void:
	_track_drag_velocity(delta)
	_drag_loose_piece()
	_drag_held_item(delta)
	_update_cursor()


## Keeps the smoothed pointer speed of the current drag. It
## only builds while a loose part, a resting screw or the
## finished item is being dragged, and it only counts as a
## throw when the speed stays past the threshold for a few
## frames in a row, so one jump of the pointer is a drag,
## never a throw.
func _track_drag_velocity(delta: float) -> void:
	var is_dragging := (
		is_instance_valid(_loose_part)
		or is_instance_valid(_loose_screw)
		or held is Repairable
	)
	if not is_dragging or delta <= 0.0:
		_drag_velocity = Vector2.ZERO
		_drag_sustain_frames = 0
		_has_throw_pointer_previous = false
		return
	var pointer := pointer_position
	if not _has_throw_pointer_previous:
		_throw_pointer_previous = pointer
		_has_throw_pointer_previous = true
		return
	var instant_velocity := (pointer - _throw_pointer_previous) / delta
	_throw_pointer_previous = pointer
	var smoothing_sec := maxf(
		G.settings.workable_cursor_smoothing_sec,
		0.001,
	)
	var weight := 1.0 - exp(-delta / smoothing_sec)
	_drag_velocity = _drag_velocity.lerp(instant_velocity, weight)
	if (
		instant_velocity.length()
		>= G.settings.workable_throw_min_speed_px_per_sec
	):
		_drag_sustain_frames += 1
	else:
		_drag_sustain_frames = 0


## The speed a piece is thrown with on release, or zero
## when the drag was slow, brief or a single jump.
func get_drag_release_velocity() -> Vector2:
	if _drag_sustain_frames < _THROW_SUSTAIN_FRAMES:
		return Vector2.ZERO
	if (
		_drag_velocity.length()
		< G.settings.workable_throw_min_speed_px_per_sec
	):
		return Vector2.ZERO
	return _drag_velocity


func _input(event: InputEvent) -> void:
	# Only track the pointer here. Presses are routed in
	# _unhandled_input. Skip the motion that Input makes up when the
	# cursor shape changes.
	if (
		event is InputEventMouse
		and event.device != _DEVICE_ID_INTERNAL
	):
		_track_pointer(event as InputEventMouse)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_level_running():
		return
	if event is InputEventMouseMotion:
		if is_instance_valid(input_owner):
			if input_owner.has_method("on_pointer_moved"):
				input_owner.on_pointer_moved(pointer_position)
			get_viewport().set_input_as_handled()
		return

	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	# Only the left button. Touch arrives as an emulated left button.
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	_track_pointer(button)

	if button.pressed:
		_is_press_used = _handle_press(pointer_position)
		if _is_press_used:
			get_viewport().set_input_as_handled()
	else:
		var is_release_used := _handle_release(pointer_position)
		if is_release_used or _is_press_used:
			get_viewport().set_input_as_handled()
		_is_press_used = false


## Takes a tool, part or item. A held tool goes back to its holder
## first.
func grab(thing: Node2D) -> void:
	if thing == held:
		return
	if is_instance_valid(held):
		_put_back_held()
	held = thing
	thing.tree_exiting.connect(_on_held_tree_exiting)
	if thing is Tool:
		(thing as Tool).pick_up()
		# Tools are their own draw group. The tool just taken rises
		# to the top of it.
		var parent := thing.get_parent()
		if is_instance_valid(parent):
			parent.move_child(thing, parent.get_child_count() - 1)
	_update_cursor()


## Empties the hand. Whoever calls it decides where the thing goes.
func release() -> void:
	if (
		is_instance_valid(held)
		and held.tree_exiting.is_connected(_on_held_tree_exiting)
	):
		held.tree_exiting.disconnect(_on_held_tree_exiting)
	held = null
	_update_cursor()


func is_empty() -> bool:
	return not is_instance_valid(held)


## The held tool, or null when the hand is empty or holds something
## else.
func get_held_tool() -> Tool:
	if held is Tool:
		return held as Tool
	return null


## Sends every press, drag and release to the microgame until it calls
## clear_input_owner().
func set_input_owner(microgame: Object) -> void:
	input_owner = microgame


func clear_input_owner(microgame: Object) -> void:
	if input_owner == microgame:
		input_owner = null


## Called by a finished item when the empty hand presses it. The hand
## holds the item where it was grabbed, tilts it with the drag speed and
## drops it on release (`Level.drop_item()`).
func drag_item(item: Repairable) -> void:
	if not is_instance_valid(item) or not is_empty():
		return
	grab(item)
	item.on_grabbed()
	_drag_offset = item.global_position - pointer_position
	_drag_tilt = item.rotation
	_drag_previous_pointer = pointer_position


## Shows the small "nope" icon next to a world position.
func show_nope(global_point: Vector2) -> void:
	%NopeIcon.global_position = global_point + _NOPE_ICON_OFFSET
	%NopeIcon.modulate.a = 1.0
	%NopeIcon.visible = true
	if is_instance_valid(_nope_tween):
		_nope_tween.kill()
	_nope_tween = create_tween()
	_nope_tween.tween_interval(G.settings.nope_icon_sec * 0.5)
	_nope_tween.tween_property(
		%NopeIcon,
		"modulate:a",
		0.0,
		G.settings.nope_icon_sec * 0.5,
	)
	_nope_tween.tween_callback(%NopeIcon.hide)


## The first point under a world position whose layer is exposed, or
## null.
func find_point(global_point: Vector2) -> InteractionPoint:
	for area in _query(global_point, Settings.PhysicsLayer.INTERACTION_POINTS):
		var point := area as InteractionPoint
		if (
			is_instance_valid(point)
			and point.is_visible_in_tree()
			and point.is_exposed()
		):
			return point
	return null


## The first exposed point lined up with a tool's working end, or
## null. Engaging lines the tool's InteractionArea up with the
## point's area; where the cursor marker sits doesn't matter.
func find_point_for_tool(tool: Tool) -> InteractionPoint:
	var shape_node := tool.get_interaction_shape()
	if not is_instance_valid(shape_node):
		return null
	if not is_instance_valid(shape_node.shape):
		return null
	var parameters := PhysicsShapeQueryParameters2D.new()
	parameters.shape = shape_node.shape
	parameters.transform = shape_node.global_transform
	parameters.collision_mask = Settings.PhysicsLayer.INTERACTION_POINTS
	parameters.collide_with_areas = true
	parameters.collide_with_bodies = false
	var space := get_world_2d().direct_space_state
	for result in space.intersect_shape(parameters, _QUERY_MAX_RESULTS):
		var point := result.collider as InteractionPoint
		if (
			is_instance_valid(point)
			and point.is_visible_in_tree()
			and point.is_exposed()
		):
			return point
	return null


## The first active surface under a world position, or null.
func find_surface(global_point: Vector2) -> Surface:
	for area in _query(global_point, Settings.PhysicsLayer.SURFACES):
		var surface := area as Surface
		if is_instance_valid(surface) and surface.is_active():
			return surface
	return null


## The press rules from tools.md "Routing a press", in order. Returns
## true when the press was used.
func _handle_press(global_point: Vector2) -> bool:
	# 1. A microgame owns input.
	if is_instance_valid(input_owner):
		if input_owner.has_method("on_pointer_pressed"):
			input_owner.on_pointer_pressed(global_point)
		return true
	# A drawer is open in the center, or one is on its way: it takes
	# every press until it is shut again.
	if _press_drawer_modal(global_point):
		return true
	return (
		_press_resting_screw(global_point)
		or _press_set_aside_layer(global_point)
		or _press_loose_part(global_point)
		or _press_drawer(global_point)
		or _press_rack(global_point)
		or _press_with_tool(global_point)
		or _press_loose_layer(global_point)
		or _press_with_empty_hand(global_point)
	)


## 2. Over a screw resting on the bench: start dragging it, empty
## handed. It seats again only when dropped close to its hole once
## its layer is back on. With anything in the hand the press does
## nothing (docs/design/screw_pullout.md).
func _press_resting_screw(global_point: Vector2) -> bool:
	var screw := G.level.get_resting_screw_at(global_point)
	if not is_instance_valid(screw):
		return false
	if screw.is_returning:
		# On its way back in. The press is used, but the
		# screw cannot be picked up until it rests.
		return true
	if is_empty() and not is_instance_valid(_loose_screw):
		_loose_screw = screw
		_loose_drag_offset = (
			screw.bench_art.global_position - global_point
		)
		screw.is_carried = true
		screw.on_picked_up()
	return true


## 3. Over a layer lying loose on the bench: start dragging it,
## empty handed. Dropped close to home once it is ready, it tweens
## back on. With anything in the hand the press does nothing.
func _press_set_aside_layer(global_point: Vector2) -> bool:
	var layer := _find_loose_layer(global_point)
	if not is_instance_valid(layer):
		return false
	if is_empty() and not is_instance_valid(_loose_layer):
		_loose_layer = layer
		_loose_drag_offset = layer.global_position - global_point
		layer.is_moving = true
	return true


## Over the item's exposed layer once its fasteners are all out:
## start dragging it off the item, empty handed.
func _press_loose_layer(global_point: Vector2) -> bool:
	if not is_empty() or is_instance_valid(_loose_layer):
		return false
	var item := G.level.active_repairable
	if not is_instance_valid(item):
		return false
	var layer := item.get_exposed_layer()
	if (
		not is_instance_valid(layer)
		or layer.is_innermost()
		or not layer.is_loose()
		or not layer.has_point(global_point)
		or is_instance_valid(find_point(global_point))
	):
		return false
	layer.take_off_for_drag()
	_loose_layer = layer
	_loose_drag_offset = layer.global_position - global_point
	return true


## While a drawer is open in the center (or still on its way), it
## takes every press. A press on one of its parts takes the part
## out and shuts the drawer behind it. A press on another shut
## drawer shuts this one and opens that one in its place. A press
## on the drawer itself does nothing. Any other press just shuts
## it.
func _press_drawer_modal(global_point: Vector2) -> bool:
	var drawer := G.level.get_open_or_opening_drawer()
	if not is_instance_valid(drawer):
		# None open or opening: a press while one shuts or takes
		# a part in is still swallowed.
		return G.level.are_drawers_busy()
	if drawer.state == Drawer.State.OPEN:
		var part := G.level.get_drawer_part_at(drawer, global_point)
		if is_instance_valid(part):
			if (
				is_empty()
				and not is_instance_valid(_loose_screw)
				and not is_instance_valid(_loose_layer)
				and not is_instance_valid(_loose_part)
			):
				_loose_part = part
				_loose_drag_offset = part.global_position - global_point
				part.is_stored = false
				part.drawer_index = -1
				drawer.close_drawer()
				G.audio.play_sound(&"click")
			return true
	var target := _find_drawer(global_point)
	if (
		is_instance_valid(target)
		and target != drawer
		and target.state == Drawer.State.CLOSED
	):
		if held is Repairable:
			drawer.close_drawer()
			return true
		var held_tool := get_held_tool()
		if is_instance_valid(held_tool):
			if held_tool.mode == Tool.Mode.IN_USE:
				# A point has the tool. Let it finish first.
				drawer.close_drawer()
				return true
			held_tool.put_away()
		G.audio.play_sound(&"whoosh")
		# Both animate at once: the opener's slide out of its
		# slot staggers it past the closer's trip home, so the
		# two never meaningfully cross in the center.
		drawer.close_drawer()
		target.open_drawer()
		return true
	if drawer.has_global_point(global_point):
		return true
	drawer.close_drawer()
	return true


## Over a part resting on the bench: start dragging it, empty
## handed. With anything in the hand the press does nothing.
func _press_loose_part(global_point: Vector2) -> bool:
	var part := G.level.get_loose_part_at(global_point)
	if not is_instance_valid(part):
		return false
	if (
		is_empty()
		and not is_instance_valid(_loose_screw)
		and not is_instance_valid(_loose_layer)
		and not is_instance_valid(_loose_part)
	):
		_loose_part = part
		_loose_drag_offset = part.global_position - global_point
	return true


## 4. Over a shut parts drawer: open it. Holding a tool puts the
## tool away first, like the rack.
func _press_drawer(global_point: Vector2) -> bool:
	var drawer := _find_drawer(global_point)
	if not is_instance_valid(drawer):
		return false
	if held is Repairable:
		return false
	var held_tool := get_held_tool()
	if is_instance_valid(held_tool):
		if held_tool.mode == Tool.Mode.IN_USE:
			# A point has the tool. Let it finish first.
			return true
		held_tool.put_away()
	G.audio.play_sound(&"whoosh")
	drawer.open_drawer()
	return true


## 5. Over a stored tool: take it. A held tool goes back first.
## Only the tool itself counts: its holder does not.
func _press_rack(global_point: Vector2) -> bool:
	var rack_tool := _find_rack_tool(global_point)
	if not is_instance_valid(rack_tool):
		return false
	var held_tool := get_held_tool()
	if is_instance_valid(held_tool) and held_tool.mode == Tool.Mode.IN_USE:
		# A point has the tool. Let it finish first.
		return true
	grab(rack_tool)
	return true


## 6. Holding a tool: its tip goes to the press, then it acts there.
## Effect tools act at the press point and stay in the hand. Engage
## tools go IN_USE on the point lined up with their working end.
func _press_with_tool(global_point: Vector2) -> bool:
	var held_tool := get_held_tool()
	if not is_instance_valid(held_tool) or held_tool.mode != Tool.Mode.HELD:
		return false
	held_tool.snap_tip_to(global_point)
	if held_tool.is_effect_tool():
		held_tool.on_effect_pressed(global_point)
		return true
	var target := find_point_for_tool(held_tool)
	if not is_instance_valid(target) or not target.can_engage():
		return false
	if target.accepts(held_tool):
		target.engage(held_tool)
	else:
		held_tool.nope()
	return true


## 8. Empty hand over a point: poke it.
## 9. Empty hand over the item: drag it if finished, or shake it.
func _press_with_empty_hand(global_point: Vector2) -> bool:
	if is_instance_valid(held):
		return false
	var item := _find_item(global_point)
	# A finished item is picked up anywhere, over its fasteners too.
	if is_instance_valid(item) and item.has_finished:
		item.on_pressed()
		return true
	var point := find_point(global_point)
	if is_instance_valid(point):
		point.on_poked()
		return true
	if is_instance_valid(item):
		item.on_pressed()
		return true
	return false


func _handle_release(global_point: Vector2) -> bool:
	if is_instance_valid(input_owner):
		if input_owner.has_method("on_pointer_released"):
			input_owner.on_pointer_released(global_point)
		return true
	var release_velocity := get_drag_release_velocity()
	if is_instance_valid(_loose_part):
		_drop_loose_part(global_point, release_velocity)
		return true
	if is_instance_valid(_loose_screw):
		_drop_loose_screw(release_velocity)
		return true
	if is_instance_valid(_loose_layer):
		_drop_loose_layer()
		return true
	if held is Repairable:
		var item := held as Repairable
		release()
		G.level.drop_item(item, release_velocity)
		return true
	return false


## Follows the pointer with the loose piece being dragged. Parts
## and screws may be carried anywhere, outside the workable area
## too. They are only set down on release, and a release outside
## the workable area sends them back in. A layer still drops at
## the bench's edge at once, instead of being carried off it.
func _drag_loose_piece() -> void:
	if is_instance_valid(_loose_part):
		# A part may be carried anywhere, over the drawers too. It
		# is only set down, fitted or put away on release.
		_loose_part.global_position = (
			pointer_position + _loose_drag_offset
		)
	elif is_instance_valid(_loose_screw):
		# A screw may be carried anywhere too. It is only set
		# down on release, and a release outside the workable
		# area sends it back in.
		_loose_screw.bench_art.global_position = (
			pointer_position + _loose_drag_offset
		)
	elif is_instance_valid(_loose_layer):
		if not G.level.is_inside_bench(pointer_position):
			_loose_layer.global_position = G.level.clamp_to_bench(
				pointer_position + _loose_drag_offset,
			)
			_drop_loose_layer()
			return
		_loose_layer.global_position = (
			pointer_position + _loose_drag_offset
		)


## Lets go of a dragged screw. Dropped close to its hole once its
## layer is back on, it arcs down into the hole. Dropped outside
## the workable area, it flies back in and comes to rest inside
## it. A fast release throws it with the cursor's motion.
## Anywhere else inside, it simply rests where it fell.
func _drop_loose_screw(release_velocity := Vector2.ZERO) -> void:
	var screw := _loose_screw
	_loose_screw = null
	if not is_instance_valid(screw):
		return
	screw.is_carried = false
	if (
		screw.can_come_back()
		and screw.bench_art.global_position.distance_to(
			screw.global_position,
		) <= G.settings.screw_seat_snap_px
	):
		screw.come_back()
		return
	if G.level.try_return_screw(screw, release_velocity):
		return
	# Set down on the table after a drag: it rolls a little.
	screw.on_set_down()


## True while this layer is being dragged across the bench.
func is_dragging_loose_layer(layer: RepairLayer) -> bool:
	return _loose_layer == layer


## The resting screw being dragged, or null.
func get_loose_screw() -> Screw:
	return _loose_screw


## The loose layer being dragged, or null.
func get_loose_layer() -> RepairLayer:
	return _loose_layer


## The loose part being dragged, or null.
func get_loose_part() -> Part:
	return _loose_part


## Lets go of a dragged part. Released over a socket, it tries to
## fit: the right part snaps in, the wrong one nopes and stays on
## the bench. Released over a drawer that may take it, the drawer
## puts it away. A drawer that is still shutting takes nothing, so
## the part is set down instead. Anywhere else it rests where it
## fell, unless that is outside the workable area, which sends
## it back in.
func _drop_loose_part(
	global_point: Vector2,
	release_velocity := Vector2.ZERO,
) -> void:
	var part := _loose_part
	_loose_part = null
	if not is_instance_valid(part):
		return
	var socket := _find_socket(global_point)
	if is_instance_valid(socket):
		socket.try_fit(part)
		if part.is_installed:
			return
		_set_down_part(part, release_velocity)
		return
	var drawer := G.level.get_drawer_at(global_point)
	if is_instance_valid(drawer) and drawer.can_take_part():
		drawer.take_part(part)
		return
	_set_down_part(part, release_velocity)


## Sets a part down on the bench where it was let go. Let go
## outside the workable area, it flies back in and comes to
## rest inside it instead of resting where it fell. A fast
## release throws it with the cursor's motion.
func _set_down_part(
	part: Part,
	release_velocity := Vector2.ZERO,
) -> void:
	if G.level.try_return_part(part, release_velocity):
		return
	part.z_index = 10


## Lets go of a dragged layer. Dropped close to home once it is
## ready to go back, it tweens into its exact place. Anywhere else
## on the bench it rests where it fell.
func _drop_loose_layer() -> void:
	var layer := _loose_layer
	_loose_layer = null
	if not is_instance_valid(layer):
		return
	layer.finish_drag()
	if (
		layer.is_ready_to_go_back()
		and layer.global_position.distance_to(
			layer.get_home_global_position(),
		) <= G.settings.layer_seat_snap_px
	):
		layer.put_back()


## Moves the dragged item with the pointer and tilts it with the sideways
## speed: right leans clockwise, left counterclockwise.
func _drag_held_item(delta: float) -> void:
	var item := held as Repairable
	if not is_instance_valid(item):
		return
	var pointer := pointer_position
	var velocity_x := (pointer.x - _drag_previous_pointer.x) / delta
	_drag_previous_pointer = pointer
	var target_tilt := (
		clampf(velocity_x / G.settings.drag_tilt_full_speed, -1.0, 1.0)
		* deg_to_rad(G.settings.drag_tilt_max_deg)
	)
	_drag_tilt = lerpf(
		_drag_tilt,
		target_tilt,
		1.0 - exp(-G.settings.drag_tilt_follow_rate * delta),
	)
	item.global_position = pointer + _drag_offset
	item.rotation = _drag_tilt


func _track_pointer(event: InputEventMouse) -> void:
	pointer_screen_position = event.position
	is_touch = event.device == InputEvent.DEVICE_ID_EMULATION


## The pointing hand when empty, an open hand when empty and over
## something it can grab (a tuggable part, a page that can flip),
## and the grabbed hand while anything is held, dragged loose or
## being tugged out. The cursor is never hidden: the arrow shape
## carries the point texture, the pointing-hand shape the open
## hand, and the drag shape the grabbed hand
## (Main._set_up_cursors).
func _update_cursor() -> void:
	if not is_inside_tree() or not _is_level_running():
		return
	if not can_process():
		_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_ARROW)
	elif _is_tugging_part():
		_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_DRAG)
	elif (
		is_instance_valid(_loose_screw)
		or is_instance_valid(_loose_layer)
		or is_instance_valid(_loose_part)
		or is_instance_valid(held)
	):
		_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_DRAG)
	elif _can_take(pointer_position):
		_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_POINTING_HAND)
	else:
		_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_ARROW)


## True while a broken part is being tugged out of its socket.
func _is_tugging_part() -> bool:
	var owner_socket := input_owner as PartSocket
	return is_instance_valid(owner_socket) and owner_socket.is_tugging()


## False for the one frame a level run on its own (F6) waits to be
## swapped for the full game, when there is no G.level yet.
func _is_level_running() -> bool:
	return is_instance_valid(G.level) and G.level.is_ancestor_of(self)


func _apply_cursor(
	to_mouse_mode: Input.MouseMode,
	to_cursor_shape: Input.CursorShape,
) -> void:
	mouse_mode = to_mouse_mode
	cursor_shape = to_cursor_shape
	# Both setters return early when nothing changes. The default shape
	# persists across mouse motion, unlike DisplayServer.cursor_set_shape().
	Input.set_mouse_mode(to_mouse_mode)
	Input.set_default_cursor_shape(to_cursor_shape)


func _can_take(global_point: Vector2) -> bool:
	if is_instance_valid(input_owner):
		# A broken part being wiggled out still shows the open hand.
		# Every other running microgame takes the arrow instead.
		var owner_socket := input_owner as PartSocket
		return (
			is_instance_valid(owner_socket)
			and owner_socket.has_tuggable_part()
		)
	var screw := G.level.get_resting_screw_at(global_point)
	if is_instance_valid(screw):
		return true
	if is_instance_valid(_find_loose_layer(global_point)):
		return true
	var item := G.level.active_repairable
	if is_instance_valid(item):
		var exposed := item.get_exposed_layer()
		if (
			is_instance_valid(exposed)
			and not exposed.is_innermost()
			and exposed.is_loose()
			and exposed.has_point(global_point)
		):
			return true
	var manual := (
		G.level.get_node_or_null("InstructionManual") as InstructionManual
	)
	if (
		is_instance_valid(manual)
		and manual.is_point_over_flippable_page(global_point)
	):
		return true
	for prop_name in ["InstructionManual", "%TicketCard"]:
		var prop := G.level.get_node_or_null(prop_name) as LiftableProp
		if not is_instance_valid(prop):
			continue
		# The open manual is covered by the page check above. Its
		# cover only offers a grab while closed.
		if (
			prop is InstructionManual
			and (prop as InstructionManual).state
			!= InstructionManual.State.CLOSED
		):
			continue
		if prop.is_point_on_prop(global_point):
			return true
	if is_instance_valid(G.level.get_loose_part_at(global_point)):
		return true
	var open_drawer := G.level.get_open_drawer()
	if (
		is_instance_valid(open_drawer)
		and is_instance_valid(
			G.level.get_drawer_part_at(open_drawer, global_point)
		)
	):
		return true
	if is_instance_valid(_find_drawer(global_point)):
		return true
	if is_instance_valid(_find_rack_tool(global_point)):
		return true
	var socket := _find_socket(global_point)
	if is_instance_valid(socket) and socket.has_tuggable_part():
		return true
	var found_item := _find_item(global_point)
	return is_instance_valid(found_item) and found_item.has_finished


func _put_back_held() -> void:
	var held_tool := get_held_tool()
	if is_instance_valid(held_tool):
		held_tool.put_away()
	else:
		release()


## The stored tool under a world position, or null. Only the
## tool's own grab area counts: its holder does not.
func _find_rack_tool(global_point: Vector2) -> Tool:
	for area in _query(global_point, Settings.PhysicsLayer.TOOLS):
		var tool := _find_tool_owner(area)
		if not is_instance_valid(tool):
			continue
		if (
			tool.mode == Tool.Mode.STORED
			or tool.mode == Tool.Mode.ENTERING
		):
			return tool
	return null


## The parts drawer under a world position, or null.
func _find_drawer(global_point: Vector2) -> Drawer:
	for area in _query(global_point, Settings.PhysicsLayer.PARTS):
		var node: Node = area
		while is_instance_valid(node):
			if node is Drawer:
				return node as Drawer
			node = node.get_parent()
	return null


## The first socket under a world position on an exposed layer, or
## null. Finished sockets still count: pressing one nopes.
func _find_socket(global_point: Vector2) -> PartSocket:
	for area in _query(
		global_point, Settings.PhysicsLayer.INTERACTION_POINTS
	):
		var socket := area as PartSocket
		if (
			is_instance_valid(socket)
			and socket.is_visible_in_tree()
			and socket.is_exposed()
		):
			return socket
	return null


func _find_tool_owner(node: Node) -> Tool:
	while is_instance_valid(node):
		if node is Tool:
			return node as Tool
		node = node.get_parent()
	return null


func _find_ready_layer(global_point: Vector2) -> RepairLayer:
	var layers := G.level.get_set_aside_layers()
	# The top of the stack first.
	for index in range(layers.size() - 1, -1, -1):
		var layer := layers[index]
		if layer.is_ready_to_go_back() and layer.has_point(global_point):
			return layer
	return null


## Any layer lying loose on the bench under a world position,
## ready or not: all of them can be dragged around.
func _find_loose_layer(global_point: Vector2) -> RepairLayer:
	var layers := G.level.get_set_aside_layers()
	# The top of the stack first.
	for index in range(layers.size() - 1, -1, -1):
		var layer := layers[index]
		if not layer.is_moving and layer.has_point(global_point):
			return layer
	return null


func _find_item(global_point: Vector2) -> Repairable:
	var item := G.level.active_repairable
	if (
		is_instance_valid(item)
		and item.mode == Repairable.Mode.UNDER_REPAIR
		and item.has_point(global_point)
	):
		return item
	return null


func _query(global_point: Vector2, mask: int) -> Array[Area2D]:
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = global_point
	parameters.collision_mask = mask
	parameters.collide_with_areas = true
	parameters.collide_with_bodies = false
	var space := get_world_2d().direct_space_state
	var areas: Array[Area2D] = []
	for result in space.intersect_point(parameters, _QUERY_MAX_RESULTS):
		var area := result.collider as Area2D
		if is_instance_valid(area):
			areas.append(area)
	return areas


func _on_held_tree_exiting() -> void:
	# The held thing was freed: empty the hand and fix the cursor (LX2).
	release()
