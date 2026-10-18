class_name PartsMenu
extends Control
## The parts menu. Pressing the drawer flies a copy of each part out
## of the drawer space into a slot here. Pressing a slot flies the
## others back and hands the chosen part over
## (docs/design/parts_bin.md).


signal part_selected(part_type: Part.Type)

## Seconds a part copy takes to fly out of or back into the drawer.
const _FLY_SEC := 0.3
## The stagger between copies, in seconds.
const _STAGGER_SEC := 0.04
const _SLOT_SIZE := Vector2(120.0, 120.0)
const _SLOT_GAP_PX := 16.0

var _is_open := false
var _is_closing := false
var _is_animating := false
var _slots: Array[Control] = []
var _slot_types: Array[Part.Type] = []
var _drawer_screen_position := Vector2.ZERO
var _tween: Tween


func _ready() -> void:
	visible = false
	%Backdrop.gui_input.connect(_on_backdrop_gui_input)


## True while the menu is up, flying or settled.
func is_open() -> bool:
	return _is_open


## True while the menu is up and not on its way out. Once a part is
## chosen or the menu is cancelled, the copies fly home but the
## bench already takes presses again.
func is_blocking_bench() -> bool:
	return _is_open and not _is_closing


## Flies the parts out of the drawer. `part_types` fills the slots.
func open_menu(
	part_types: Array[Part.Type],
	drawer_screen_position: Vector2,
) -> void:
	if _is_open and not _is_animating:
		return
	# Reopening mid-close is fine: the old copies go away and a fresh
	# set flies out.
	_is_open = true
	_is_closing = false
	_is_animating = true
	%Backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer_screen_position = drawer_screen_position
	_build_slots(part_types)
	visible = true
	_kill_tween()
	_tween = create_tween()
	for index in _slots.size():
		var slot := _slots[index]
		var target := _slot_target(index, part_types.size())
		_tween.tween_callback(_fly_slot.bind(slot, target))
		_tween.tween_interval(_STAGGER_SEC)
	_tween.tween_callback(_on_flown.bind(true))


## Flies every part back into the drawer with nothing taken.
func cancel() -> void:
	if not _is_open or _is_animating:
		return
	_is_animating = true
	_fly_back(-1)


func _build_slots(part_types: Array[Part.Type]) -> void:
	for slot in _slots:
		if is_instance_valid(slot):
			slot.free()
	_slots.clear()
	_slot_types = part_types.duplicate()
	for index in part_types.size():
		var slot := _build_slot(part_types[index])
		slot.position = _drawer_screen_position - _SLOT_SIZE * 0.5
		slot.scale = Vector2(0.3, 0.3)
		slot.modulate.a = 0.0
		slot.gui_input.connect(_on_slot_gui_input.bind(index))
		%Slots.add_child(slot)
		_slots.append(slot)


func _build_slot(part_type: Part.Type) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = _SLOT_SIZE
	slot.size = _SLOT_SIZE
	slot.pivot_offset = _SLOT_SIZE * 0.5
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	# The pointing-hand shape shows the open-hand grab texture
	# registered for it in Main._set_up_cursors.
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var background := ColorRect.new()
	background.color = Color(0.12, 0.1, 0.08, 0.9)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(background)

	var art := Polygon2D.new()
	art.polygon = Part.get_polygon(part_type)
	art.color = Part.get_color(part_type)
	art.position = Vector2(_SLOT_SIZE.x * 0.5, _SLOT_SIZE.y * 0.38)
	art.scale = Vector2(1.4, 1.4)
	slot.add_child(art)

	var label := Label.new()
	label.text = Part.get_display_name(part_type)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -36.0
	label.offset_bottom = -8.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	return slot


func _slot_target(index: int, count: int) -> Vector2:
	var total_width := (
		count * _SLOT_SIZE.x + (count - 1) * _SLOT_GAP_PX
	)
	var start_x := (size.x - total_width) * 0.5
	return Vector2(
		start_x + index * (_SLOT_SIZE.x + _SLOT_GAP_PX),
		size.y * 0.5 - _SLOT_SIZE.y * 0.5,
	)


func _choose(index: int) -> void:
	if not _is_open or _is_animating:
		return
	_is_animating = true
	_fly_back(index)
	part_selected.emit(_slot_types[index])


## Flies every slot but `chosen_index` back into the drawer, fades the
## menu and hides it. The chosen slot only fades.
func _fly_back(chosen_index: int) -> void:
	_is_closing = true
	# Closing: the bench takes presses again right away, even while
	# the copies are still flying home.
	%Backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_tween()
	_tween = create_tween().set_parallel()
	for index in _slots.size():
		var slot := _slots[index]
		if index == chosen_index:
			_tween.tween_property(slot, "modulate:a", 0.0, _FLY_SEC * 0.5)
		else:
			_tween.tween_property(
				slot,
				"position",
				_drawer_screen_position - _SLOT_SIZE * 0.5,
				_FLY_SEC,
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_tween.tween_property(slot, "scale", Vector2(0.3, 0.3), _FLY_SEC)
			_tween.tween_property(slot, "modulate:a", 0.0, _FLY_SEC)
	_tween.chain().tween_callback(_on_flown.bind(false))


func _fly_slot(slot: Control, target: Vector2) -> void:
	# Bound to the slot, so freeing the slot ends its flight quietly.
	var tween := slot.create_tween().set_parallel()
	tween.tween_property(slot, "position", target, _FLY_SEC).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot, "scale", Vector2.ONE, _FLY_SEC)
	tween.tween_property(slot, "modulate:a", 1.0, _FLY_SEC)


func _on_flown(opened: bool) -> void:
	_is_animating = false
	if not opened:
		_is_open = false
		_is_closing = false
		visible = false
		for slot in _slots:
			slot.queue_free()
		_slots.clear()


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index
		== MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
	):
		# Take the press, so it cannot also reach the bench behind
		# the menu (the drawer, the tool rack, the item).
		accept_event()
		cancel()


func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index
		== MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
	):
		accept_event()
		_choose(index)


func _kill_tween() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
