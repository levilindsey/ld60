class_name RepairLayer
extends Node2D
## One layer of an item: a cover, a shell, the mechanism inside
## (docs/design/repairables.md).
##
## The item's `Layers` children are ordered innermost first. The exposed
## layer is the outermost one still on. Once its fasteners are out, it
## lifts off by itself and moves to the set-aside spot. When the work
## under it is done, it gets the outline, and a press puts it back.


## How far a set-aside layer may be turned from how it sits on the
## item, in degrees. A fresh turn in that range is picked each time
## it is set aside.
const _SET_ASIDE_MAX_TURN_DEG := 20.0
const _PULSE_SCALE := 1.08
const _PULSE_SEC := 0.3

## The art that decals parent to and clip against. Points and surfaces
## are its siblings, not its children. A ColorRect, Sprite2D or
## Polygon2D, so a press can be tested against it.
@export var art: CanvasItem

## The item this layer belongs to. The item sets it.
var item: Repairable
## False while the layer is off the item.
var is_on := true
## True from the moment it starts to lift off or go back until it
## lands.
var is_moving := false

var _home_parent: Node
var _home_index := 0
var _home_position := Vector2.ZERO
var _home_rotation := 0.0
var _home_scale := Vector2.ONE
## The scale it rests at, on the item or at the set-aside spot.
var _rest_scale := Vector2.ONE
## The turn it rests at on the set-aside spot.
var _set_aside_rotation := 0.0
var _move_tween: Tween
var _pulse_tween: Tween
var _outline_hint: OutlineHint
var _outlined_art: Sprite2D
var _art_material_before_outline: Material


func _ready() -> void:
	G.check(is_instance_valid(art))
	_home_parent = get_parent()
	_home_index = get_index()
	_home_position = position
	_home_rotation = rotation
	_home_scale = scale
	_rest_scale = scale


## The points on this layer. Points inside the art don't count.
func get_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for node in _get_parts():
		if node is InteractionPoint:
			points.append(node as InteractionPoint)
	return points


## The FASTENER points on this layer.
func get_fasteners() -> Array[InteractionPoint]:
	var fasteners: Array[InteractionPoint] = []
	for point in get_points():
		if point.role == InteractionPoint.Role.FASTENER:
			fasteners.append(point)
	return fasteners


func get_surfaces() -> Array[Surface]:
	var surfaces: Array[Surface] = []
	for node in _get_parts():
		if node is Surface:
			surfaces.append(node as Surface)
	return surfaces


## True while this layer is the outermost layer on the item and isn't
## moving.
func is_exposed() -> bool:
	return (
		is_on
		and not is_moving
		and is_instance_valid(item)
		and item.get_exposed_layer() == self
	)


## The innermost layer is never removed.
func is_innermost() -> bool:
	return (
		is_instance_valid(item)
		and not item.layers.is_empty()
		and item.layers[0] == self
	)


## True when no fastener holds this layer on.
func is_loose() -> bool:
	for fastener in get_fasteners():
		if fastener.is_fastened():
			return false
	return true


## True when this set-aside layer can go back on: it is next in line
## and every required point on the layers under it is FINISHED.
func is_ready_to_go_back() -> bool:
	return (
		not is_on
		and not is_moving
		and is_instance_valid(item)
		and item.get_next_layer_to_put_back() == self
		and item.are_points_under_finished(self)
	)


## Called by a point on this layer when it finishes. The last fastener
## out makes the layer lift off.
func on_point_finished(point: InteractionPoint) -> void:
	if (
		point.role == InteractionPoint.Role.FASTENER
		and is_on
		and not is_moving
		and not is_innermost()
		and is_loose()
	):
		lift_off()


## Lifts this loose layer off the item after a short delay and moves it
## to the set-aside spot, shrinking a little.
func lift_off() -> void:
	G.check(not is_innermost())
	is_moving = true
	_kill_move_tween()
	_move_tween = create_tween()
	_move_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_move_tween.tween_interval(G.settings.layer_lift_delay_sec)
	_move_tween.tween_callback(_start_lift)


## Puts this set-aside layer back on the item. Its fasteners come back
## raised and loose, in install mode.
func put_back() -> void:
	G.check(not is_on)
	is_on = true
	is_moving = true
	_stop_outline()
	reparent(_home_parent)
	_home_parent.move_child(
		self,
		mini(_home_index, _home_parent.get_child_count() - 1),
	)
	reset_physics_interpolation()
	G.audio.play_sound(&"whoosh")
	_tween_to(_home_position, _home_rotation, _home_scale, _on_put_back)


## Starts or stops the outline that says this layer can go back on.
func update_outline() -> void:
	if is_ready_to_go_back():
		_start_outline()
	else:
		_stop_outline()


## True while the outline that says this layer can go back on shows.
func is_showing_outline() -> bool:
	if is_instance_valid(_outline_hint) and _outline_hint.is_active():
		return true
	return is_instance_valid(_outlined_art)


## One short pulse, the hint that this layer can go back on.
func pulse() -> void:
	if is_moving:
		return
	if is_instance_valid(_pulse_tween):
		_pulse_tween.kill()
	scale = _rest_scale
	_pulse_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	_pulse_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_pulse_tween.tween_property(
		self,
		"scale",
		_rest_scale * _PULSE_SCALE,
		_PULSE_SEC * 0.5,
	)
	_pulse_tween.tween_property(self, "scale", _rest_scale, _PULSE_SEC * 0.5)


## True when a world position is on this layer's art.
func has_point(global_point: Vector2) -> bool:
	if not is_instance_valid(art) or not art.is_visible_in_tree():
		return false
	var local_point := (
		art.get_global_transform().affine_inverse() * global_point
	)
	if art is Control:
		var control := art as Control
		return Rect2(Vector2.ZERO, control.size).has_point(local_point)
	if art is Sprite2D:
		return (art as Sprite2D).get_rect().has_point(local_point)
	if art is Polygon2D:
		var polygon_art := art as Polygon2D
		return Geometry2D.is_point_in_polygon(
			local_point - polygon_art.offset,
			polygon_art.polygon,
		)
	return false


func _start_lift() -> void:
	is_on = false
	var stack_index := G.level.get_set_aside_layers().size()
	reparent(G.level.get_set_aside_spot())
	reset_physics_interpolation()
	G.audio.play_sound(&"whoosh")
	_set_aside_rotation = _home_rotation + randf_range(
		-deg_to_rad(_SET_ASIDE_MAX_TURN_DEG),
		deg_to_rad(_SET_ASIDE_MAX_TURN_DEG),
	)
	_tween_to(
		G.settings.set_aside_stack_offset * stack_index,
		_set_aside_rotation,
		scale * G.settings.set_aside_scale,
		_on_lifted,
	)


func _on_lifted() -> void:
	is_moving = false
	item.on_layer_removed(self)


func _on_put_back() -> void:
	is_moving = false
	for fastener in get_fasteners():
		fastener.set_install_mode()
	G.audio.play_sound(&"thud")
	item.on_layer_installed(self)


func _tween_to(
	to_position: Vector2,
	to_rotation: float,
	to_scale: Vector2,
	on_done: Callable,
) -> void:
	_kill_move_tween()
	if is_instance_valid(_pulse_tween):
		_pulse_tween.kill()
	_rest_scale = to_scale
	_move_tween = (
		create_tween()
		.set_parallel()
		.set_trans(Tween.TRANS_QUAD)
		.set_ease(Tween.EASE_IN_OUT)
	)
	_move_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var duration_sec := G.settings.layer_move_sec
	_move_tween.tween_property(self, "position", to_position, duration_sec)
	_move_tween.tween_property(self, "rotation", to_rotation, duration_sec)
	_move_tween.tween_property(self, "scale", to_scale, duration_sec)
	_move_tween.chain().tween_callback(on_done)


func _kill_move_tween() -> void:
	if is_instance_valid(_move_tween):
		_move_tween.kill()


func _start_outline() -> void:
	if is_showing_outline():
		return
	if art is Sprite2D:
		if not is_instance_valid(G.settings.outline_hint_material):
			return
		_outlined_art = art as Sprite2D
		_art_material_before_outline = OutlineHint.apply_to_sprite(
			_outlined_art,
		)
		return
	if not is_instance_valid(_outline_hint):
		var points := OutlineHint.get_art_polygon(art)
		if points.is_empty():
			return
		_outline_hint = OutlineHint.new()
		art.add_child(_outline_hint)
		_outline_hint.polygon = points
	_outline_hint.set_active(true)


func _stop_outline() -> void:
	if is_instance_valid(_outline_hint):
		_outline_hint.set_active(false)
	if is_instance_valid(_outlined_art):
		OutlineHint.remove_from_sprite(
			_outlined_art,
			_art_material_before_outline,
		)
	_outlined_art = null
	_art_material_before_outline = null


## The points and surfaces under this layer, outside the art.
func _get_parts() -> Array[Node]:
	var parts: Array[Node] = []
	_collect_parts(self, parts)
	return parts


func _collect_parts(node: Node, parts: Array[Node]) -> void:
	for child in node.get_children():
		if (
			child == art
			or child is RepairLayer
			or child.is_queued_for_deletion()
		):
			continue
		if child is InteractionPoint or child is Surface:
			parts.append(child)
		else:
			_collect_parts(child, parts)
