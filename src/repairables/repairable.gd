class_name Repairable
extends Node2D
## An item on the bench: a stack of layers with points to fix
## (docs/design/repairables.md).
##
## The item is finished when every layer is back on, every required
## point is FINISHED and every fastener is in.
##
## It also plays its own trip through the shop (docs/design/outbox.md):
## `arrive()` drops it onto the bench, a finished item glows and can be
## dragged (`on_grabbed()`, `return_to()`), and `leave()` sends it off
## through the outbox. Every item scene needs a `%DropArea` on the
## REPAIRABLES physics layer for the outbox to detect.


signal layer_removed(layer: RepairLayer)
signal layer_installed(layer: RepairLayer)
signal point_finished(point: InteractionPoint)
## The arrival is over. The item sits on the bench and its clock runs.
signal landed
signal finished
## The item has slid off the screen into the outbox.
signal departed

enum Type {
	TEST_FLAT_HEAD_SCREW_REPAIRABLE,
}

enum Mode {
	ENTERING,
	LEAVING,
	UNDER_REPAIR,
}

## How many times the item jerks when an unfinished item is pressed.
const _SHAKE_STEPS := 4
## The color a finished item pulses to, and the seconds of half a pulse.
const _GLOW_COLOR := Color(1.3, 1.25, 0.85)
const _GLOW_HALF_PULSE_SEC := 0.6

@export var item_name := ""
## The customer's complaint, shown on the ticket.
@export_multiline var ticket := ""
@export var par_time_sec := 90.0

var mode := Mode.ENTERING
## The layers, innermost first. Collected from `%Layers`.
var layers: Array[RepairLayer] = []
## True while the item is finished.
var has_finished := false
## This repair's score: its defects and its time (`quality.md`). The
## repair time counts unpaused seconds from landing to `finished`.
var quality := RepairQuality.new()

## What the outbox tests for overlap.
var drop_area: Area2D:
	get:
		return %DropArea

var _shake_tween: Tween
var _motion_tween: Tween
var _glow_tween: Tween
var _outlined_art: CanvasItem
var _art_material_before_outline: Material


func _ready() -> void:
	for child in %Layers.get_children():
		if child is RepairLayer:
			var layer := child as RepairLayer
			layer.item = self
			layers.append(layer)
	G.check(not layers.is_empty())
	# The repair clock only runs from landing to finished.
	set_physics_process(false)


# The paused tree skips this, so the clock only counts unpaused time.
func _physics_process(delta: float) -> void:
	quality.repair_time_sec += delta


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


## Drops the item in from where it is and lands it on a world position.
## It starts turned a little, overshoots and straightens as it lands.
## `landed` fires at the end, and then the item is UNDER_REPAIR.
func arrive(target_global_position: Vector2) -> void:
	mode = Mode.ENTERING
	var angle_max := deg_to_rad(G.settings.item_arrival_angle_max_deg)
	rotation = randf_range(-angle_max, angle_max)
	_start_motion(
		target_global_position,
		0.0,
		G.settings.item_arrival_sec,
		Tween.TRANS_BACK,
		Tween.EASE_OUT,
	)
	_motion_tween.tween_callback(_land)


## The hand picked the item up. Whatever move was running stops.
func on_grabbed() -> void:
	_kill_motion_tween()


## Eases the item, straightened, to a world position. The hand calls it
## when a dragged item is dropped away from the outbox.
func return_to(target_global_position: Vector2) -> void:
	_start_motion(
		target_global_position,
		0.0,
		G.settings.item_return_sec,
		Tween.TRANS_QUAD,
		Tween.EASE_OUT,
	)


## Sends the item into the outbox: it drops into the tray, then slides to
## the exit. `departed` fires at the end and the item frees itself.
func leave(
	tray_global_position: Vector2,
	exit_global_position: Vector2,
) -> void:
	mode = Mode.LEAVING
	set_physics_process(false)
	_start_motion(
		tray_global_position,
		0.0,
		G.settings.item_tray_drop_sec,
		Tween.TRANS_QUAD,
		Tween.EASE_IN,
	)
	_motion_tween.tween_callback(G.audio.play_sound.bind("thud"))
	_motion_tween.tween_property(
		self,
		"global_position",
		exit_global_position,
		G.settings.item_leave_sec,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_motion_tween.tween_callback(_depart)


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


## Starts a move to a position and a rotation that replaces any move in
## progress. The tween runs in physics time, as physics interpolation
## wants, and leaves its tail open for the caller to add steps.
func _start_motion(
	target_global_position: Vector2,
	target_rotation: float,
	duration_sec: float,
	transition: Tween.TransitionType,
	easing: Tween.EaseType,
) -> void:
	_kill_motion_tween()
	_motion_tween = create_tween()
	_motion_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_motion_tween.set_trans(transition).set_ease(easing)
	_motion_tween.tween_property(
		self,
		"global_position",
		target_global_position,
		duration_sec,
	)
	_motion_tween.parallel().tween_property(
		self,
		"rotation",
		target_rotation,
		duration_sec,
	)


func _kill_motion_tween() -> void:
	if is_instance_valid(_motion_tween):
		_motion_tween.kill()


func _land() -> void:
	mode = Mode.UNDER_REPAIR
	quality.par_time_sec = par_time_sec
	set_physics_process(true)
	G.audio.play_sound("thud")
	landed.emit()


func _depart() -> void:
	departed.emit()
	queue_free()


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
		_play_finish_payoff()
		finished.emit()
	else:
		_stop_glow()
		# Undoing the work starts the clock again.
		set_physics_process(mode == Mode.UNDER_REPAIR)


## A ding, a burst of sparkles and a glow that lasts until the item goes.
## The clock stops.
func _play_finish_payoff() -> void:
	set_physics_process(false)
	G.audio.play_sound("ding")
	if is_instance_valid(G.settings.finish_sparkle_scene):
		var sparkle: CPUParticles2D = (
			G.settings.finish_sparkle_scene.instantiate()
		)
		add_child(sparkle)
		sparkle.finished.connect(sparkle.queue_free)
	_start_glow()


## The finished item pulses, and its top layer gets the outline when its
## art can show it.
func _start_glow() -> void:
	_stop_glow()
	var outline_material := G.settings.finished_outline_material
	var layer := get_exposed_layer()
	if (
		is_instance_valid(outline_material)
		and is_instance_valid(layer)
		and layer.art is Sprite2D
	):
		_outlined_art = layer.art
		_art_material_before_outline = _outlined_art.material
		_outlined_art.material = outline_material
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(
		self,
		"modulate",
		_GLOW_COLOR,
		_GLOW_HALF_PULSE_SEC,
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(
		self,
		"modulate",
		Color.WHITE,
		_GLOW_HALF_PULSE_SEC,
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_glow() -> void:
	if is_instance_valid(_glow_tween):
		_glow_tween.kill()
	modulate = Color.WHITE
	if is_instance_valid(_outlined_art):
		_outlined_art.material = _art_material_before_outline
	_outlined_art = null
	_art_material_before_outline = null
