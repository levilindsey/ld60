class_name Repairable
extends Node2D
## An item on the bench: a stack of layers with points to fix
## (docs/design/repairables.md).
##
## The item is finished when every layer is back on, every required
## point is FINISHED and every fastener is in.


signal layer_removed(layer: RepairLayer)
signal layer_installed(layer: RepairLayer)
signal point_finished(point: InteractionPoint)
signal finished

enum Type {
	TEST_FLAT_HEAD_SCREW_REPAIRABLE,
}

enum Mode {
	ENTERING,
	LEAVING,
	UNDER_REPAIR,
}

const ROTATE_DURATION_SEC := 0.3
const POSITION_DURATION_SEC := 0.3

const ROTATION_OFFSET_MAX := PI * 0.1

## How many times the item jerks when an unfinished item is pressed.
const _SHAKE_STEPS := 4

@export var item_name := ""
## The customer's complaint, shown on the ticket.
@export_multiline var ticket := ""
@export var par_time_sec := 90.0

var mode := Mode.ENTERING
## The layers, innermost first. Collected from `%Layers`.
var layers: Array[RepairLayer] = []
## True while the item is finished.
var has_finished := false

var position_tween: Tween
var rotation_tween: Tween

var _shake_tween: Tween


func _ready() -> void:
	for child in %Layers.get_children():
		if child is RepairLayer:
			var layer := child as RepairLayer
			layer.item = self
			layers.append(layer)
	G.check(not layers.is_empty())


## The outermost layer still on, or null.
func get_exposed_layer() -> RepairLayer:
	for index in range(layers.size() - 1, -1, -1):
		if layers[index].is_on:
			return layers[index]
	return null


## The set-aside layer that goes back on next: the last one taken off.
func get_next_layer_to_put_back() -> RepairLayer:
	for layer in layers:
		if not layer.is_on:
			return layer
	return null


## True when every required point on the layers under a layer is
## FINISHED.
func are_points_under_finished(layer: RepairLayer) -> bool:
	for under_layer in layers:
		if under_layer == layer:
			return true
		for point in under_layer.get_points():
			if point.needs_work():
				return false
	return true


## The required points that are not FINISHED yet, on every layer.
func get_remaining_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for layer in layers:
		for point in layer.get_points():
			if point.needs_work():
				points.append(point)
	return points


## True when every layer is back on, every required point is FINISHED
## and every fastener is in. A required fastener only counts as
## FINISHED once it was taken out and driven back in.
func is_finished() -> bool:
	for layer in layers:
		if not layer.is_on or layer.is_moving:
			return false
		for point in layer.get_points():
			if point.needs_work():
				return false
			if (
				point.role == InteractionPoint.Role.FASTENER
				and not point.is_fastened()
			):
				return false
	return true


## True when a world position is on a layer that is on the item.
func has_point(global_point: Vector2) -> bool:
	for layer in layers:
		if layer.is_on and not layer.is_moving and layer.has_point(global_point):
			return true
	return false


## The empty hand pressed the item (tools.md rule 7). A finished item
## goes into the hand. An unfinished one shakes and hints at what is
## left.
func on_pressed() -> void:
	if has_finished:
		G.level.hand.drag_item(self)
		return
	shake()
	G.audio.play_sound("hmm")
	pulse_remaining_points()


## Pulses the required points that still need work and can be reached
## now. If there are none, pulses the layer that is ready to go back on.
func pulse_remaining_points() -> void:
	var is_any_pulsed := false
	for point in get_remaining_points():
		if point.is_exposed():
			point.pulse()
			is_any_pulsed = true
	if is_any_pulsed:
		return
	var layer := get_next_layer_to_put_back()
	if is_instance_valid(layer) and layer.is_ready_to_go_back():
		layer.pulse()


## A small sideways shake that says "not done yet".
func shake() -> void:
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	%Layers.position = Vector2.ZERO
	_shake_tween = create_tween()
	_shake_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var step_sec := G.settings.item_shake_sec / (_SHAKE_STEPS + 1)
	for step in _SHAKE_STEPS:
		var direction := 1.0 if step % 2 == 0 else -1.0
		_shake_tween.tween_property(
			%Layers,
			"position",
			Vector2(direction * G.settings.item_shake_px, 0.0),
			step_sec,
		)
	_shake_tween.tween_property(%Layers, "position", Vector2.ZERO, step_sec)


## Called by a point when it finishes.
func on_point_finished(point: InteractionPoint) -> void:
	point_finished.emit(point)
	_update_state()


## Called by a layer when it reaches the set-aside spot.
func on_layer_removed(layer: RepairLayer) -> void:
	layer_removed.emit(layer)
	# A layer with no fasteners is loose as soon as it is exposed, so it
	# lifts right after the layer above it.
	var exposed := get_exposed_layer()
	if (
		is_instance_valid(exposed)
		and not exposed.is_moving
		and not exposed.is_innermost()
		and exposed.is_loose()
	):
		exposed.lift_off()
	_update_state()


## Called by a layer when it is back on the item.
func on_layer_installed(layer: RepairLayer) -> void:
	layer_installed.emit(layer)
	_update_state()


func tween_rotation(p_rotation: float, ease := Tween.EASE_IN_OUT) -> void:
	if is_instance_valid(rotation_tween):
		rotation_tween.kill()
	rotation_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(ease)
	rotation_tween.tween_property(
		self,
		"rotation",
		p_rotation,
		ROTATE_DURATION_SEC,
	)


func tween_position(
	p_global_position: Vector2,
	ease := Tween.EASE_IN_OUT,
) -> void:
	if is_instance_valid(position_tween):
		position_tween.kill()
	position_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(ease)
	position_tween.tween_property(
		self,
		"global_position",
		p_global_position,
		POSITION_DURATION_SEC,
	)


func _update_state() -> void:
	for layer in layers:
		layer.update_glow()
	var is_now_finished := is_finished()
	if is_now_finished == has_finished:
		return
	has_finished = is_now_finished
	if has_finished:
		G.print(
			"Item finished: %s" % item_name,
			ScaffolderLog.CATEGORY_GAME_STATE,
		)
		finished.emit()
