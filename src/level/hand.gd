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
	_drag_held_item(delta)
	_update_cursor()


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
	return (
		_press_resting_screw(global_point)
		or _press_set_aside_layer(global_point)
		or _press_drawer(global_point)
		or _press_rack(global_point)
		or _press_with_part(global_point)
		or _press_with_tool(global_point)
		or _press_with_empty_hand(global_point)
	)


## 2. Over a screw resting on the bench: once its layer is back on, send it
## back to its hole, whatever the hand holds. Before that the press does
## nothing (docs/design/screw_pullout.md).
func _press_resting_screw(global_point: Vector2) -> bool:
	var screw := G.level.get_resting_screw_at(global_point)
	if not is_instance_valid(screw):
		return false
	if screw.can_come_back():
		screw.come_back()
	return true


## 3. Over a set-aside layer that is ready to go back: put it back.
func _press_set_aside_layer(global_point: Vector2) -> bool:
	var layer := _find_ready_layer(global_point)
	if not is_instance_valid(layer):
		return false
	layer.put_back()
	return true


## 4. Over the parts drawer: holding a part returns it. Holding a tool
## puts it away first. Empty-handed, the parts menu opens.
func _press_drawer(global_point: Vector2) -> bool:
	var bin := _find_parts_bin(global_point)
	if not is_instance_valid(bin):
		return false
	if held is Part:
		bin.take_back(held as Part)
		return true
	if held is Repairable:
		return false
	var held_tool := get_held_tool()
	if is_instance_valid(held_tool):
		if held_tool.mode == Tool.Mode.IN_USE:
			# A point has the tool. Let it finish first.
			return true
		held_tool.put_away()
	bin.open_menu()
	return true


## 7. Holding a part: a press over a socket tries to fit it. Any other
## press nopes and keeps the part. The drawer press comes first.
func _press_with_part(global_point: Vector2) -> bool:
	var part := held as Part
	if not is_instance_valid(part):
		return false
	var socket := _find_socket(global_point)
	if is_instance_valid(socket):
		return socket.try_fit(part)
	part.nope()
	return true


## 5. Over the tool rack: take that tool. A held tool goes back first.
func _press_rack(global_point: Vector2) -> bool:
	var rack_tool := _find_rack_tool(global_point)
	if not is_instance_valid(rack_tool):
		return false
	var held_tool := get_held_tool()
	if is_instance_valid(held_tool) and held_tool.mode == Tool.Mode.IN_USE:
		# A point has the tool. Let it finish first.
		return true
	if rack_tool != held:
		grab(rack_tool)
	else:
		# Its own empty holder: put it back.
		rack_tool.put_away()
	return true


## 6. Holding a tool: its tip goes to the press, then it acts there.
func _press_with_tool(global_point: Vector2) -> bool:
	var held_tool := get_held_tool()
	if not is_instance_valid(held_tool) or held_tool.mode != Tool.Mode.HELD:
		return false
	held_tool.snap_tip_to(global_point)
	var target := find_point(global_point)
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
	if held is Repairable:
		var item := held as Repairable
		release()
		G.level.drop_item(item)
		return true
	return false


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
## something it can grab, a drag hand while an item is held, hidden
## while a tool is held. The arrow shape carries the point texture
## and the pointing-hand shape the grab one (Main._set_up_cursors).
func _update_cursor() -> void:
	if not is_inside_tree() or not _is_level_running():
		return
	if not can_process():
		_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_ARROW)
	elif held is Repairable:
		# The item is drawn at the pointer, so keep the pointer visible.
		_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_DRAG)
	elif is_instance_valid(held):
		_apply_cursor(Input.MOUSE_MODE_HIDDEN, Input.CURSOR_ARROW)
	elif _can_take(pointer_position):
		_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_POINTING_HAND)
	else:
		_apply_cursor(Input.MOUSE_MODE_VISIBLE, Input.CURSOR_ARROW)


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
	if is_instance_valid(screw) and screw.can_come_back():
		return true
	if is_instance_valid(_find_ready_layer(global_point)):
		return true
	if is_instance_valid(_find_parts_bin(global_point)):
		return true
	if is_instance_valid(_find_rack_tool(global_point)):
		return true
	var socket := _find_socket(global_point)
	if is_instance_valid(socket) and socket.has_tuggable_part():
		return true
	var item := _find_item(global_point)
	return is_instance_valid(item) and item.has_finished


func _put_back_held() -> void:
	var held_tool := get_held_tool()
	if is_instance_valid(held_tool):
		held_tool.put_away()
	else:
		release()


## The stored tool under a world position, either the tool itself or
## its holder, or null. Pressing the held tool's own holder returns the
## held tool.
func _find_rack_tool(global_point: Vector2) -> Tool:
	var mask := (
		Settings.PhysicsLayer.TOOLS | Settings.PhysicsLayer.TOOL_HOLDERS
	)
	for area in _query(global_point, mask):
		var tool: Tool = null
		if area is ToolHolder:
			tool = G.level.tools_by_type.get((area as ToolHolder).type)
		else:
			tool = _find_tool_owner(area)
		if not is_instance_valid(tool):
			continue
		if (
			tool.mode == Tool.Mode.STORED
			or tool.mode == Tool.Mode.ENTERING
			or (area is ToolHolder and tool == held)
		):
			return tool
	return null


## The parts drawer under a world position, or null.
func _find_parts_bin(global_point: Vector2) -> PartsBin:
	for area in _query(global_point, Settings.PhysicsLayer.PARTS):
		var node: Node = area
		while is_instance_valid(node):
			if node is PartsBin:
				return node as PartsBin
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
