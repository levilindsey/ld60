class_name InteractionPoint
extends Area2D
## Something on an item that a tool acts on: a screw, a clip, a fault.
##
## A point only reacts while its layer is exposed, the outermost layer
## still on the item (docs/design/repairables.md "Points").


enum Type {
	FLAT_HEAD_SCREW,
	PART_SOCKET,
	GRIME_SPOT,
	DUST_CLUMP,
	FAN,
	STUCK_PART,
	BENT_PART,
	SEAT_PART,
	CRACK,
	PHILLIPS_SCREW,
	RUST_SPOT,
}

enum Mode {
	UNSTARTED,
	ACTIVE,
	FINISHED,
}

enum Role {
	## Holds its layer on, like a screw or a clip.
	FASTENER,
	## A fault that must be fixed.
	REPAIR,
}

const _PULSE_SCALE := 1.6
const _POKE_ANGLE_RAD := 0.25

@export var type := Type.FLAT_HEAD_SCREW
@export var role := Role.REPAIR
## Optional points are extras, such as a coin under the dust. The item
## can finish without them.
@export var is_required := true
## The tools this point reacts to. Any other tool nopes.
@export var accepted_tools: Array[Tool.Type] = []
## What this point turns into when it breaks. Null means it can't break.
@export var broken_scene: PackedScene

var mode := Mode.UNSTARTED
## The tool that is IN_USE on this point, or null.
var engaged_tool: Tool

var _pulse_tween: Tween
var _poke_tween: Tween
var _hint_hint: OutlineHint
var _is_hint_active := false


func _ready() -> void:
	G.check(monitorable)
	G.check(collision_layer == Settings.PhysicsLayer.INTERACTION_POINTS)


func _physics_process(_delta: float) -> void:
	if is_instance_valid(engaged_tool):
		place_engaged_tool()


## The engaged tool is a puppet: this places it every frame, working
## end on the point. Microgames override it to move the tool their
## own way.
func place_engaged_tool() -> void:
	engaged_tool.place_work_end(global_position)


## The layer this point belongs to, or null.
func get_layer() -> RepairLayer:
	var node := get_parent()
	while is_instance_valid(node):
		if node is RepairLayer:
			return node as RepairLayer
		node = node.get_parent()
	return null


## The item this point belongs to, or null.
func get_item() -> Repairable:
	var layer := get_layer()
	if is_instance_valid(layer):
		return layer.item
	return null


## True while this point's layer is the outermost layer still on.
func is_exposed() -> bool:
	var layer := get_layer()
	return is_instance_valid(layer) and layer.is_exposed()


func accepts(tool: Tool) -> bool:
	return accepted_tools.has(tool.type)


## True when a tool press here would start something.
func can_engage() -> bool:
	return (
		mode == Mode.UNSTARTED
		and is_exposed()
		and is_visible_in_tree()
	)


## True while this point is required and not FINISHED.
func needs_work() -> bool:
	return is_required and mode != Mode.FINISHED


## True while this FASTENER holds its layer on.
func is_fastened() -> bool:
	return role == Role.FASTENER and mode != Mode.FINISHED


## Called on each FASTENER when its layer goes back on.
func set_install_mode() -> void:
	mode = Mode.UNSTARTED


## Starts this point's microgame with a tool. The tool goes IN_USE and
## this point places it until finish() or release_tool().
func engage(tool: Tool) -> void:
	engaged_tool = tool
	mode = Mode.ACTIVE
	tool.start_use(self)


## Lets go of the engaged tool, which goes back to the hand.
func release_tool() -> void:
	var tool := engaged_tool
	engaged_tool = null
	if is_instance_valid(tool):
		tool.stop_use()


## Marks this point done and tells its layer and its item.
func finish() -> void:
	mode = Mode.FINISHED
	release_tool()
	var layer := get_layer()
	if is_instance_valid(layer):
		layer.on_point_finished(self)
	var item := get_item()
	if is_instance_valid(item):
		item.on_point_finished(self)


## The empty hand pressed this point: the "inspect" action. Points
## override it to squeak, rattle or jerk.
func on_poked() -> void:
	G.audio.play_sound(&"click")
	if is_instance_valid(_poke_tween):
		_poke_tween.kill()
	rotation = 0.0
	_poke_tween = create_tween()
	var step_sec := G.settings.point_pulse_sec / 3.0
	_poke_tween.tween_property(self, "rotation", _POKE_ANGLE_RAD, step_sec)
	_poke_tween.tween_property(self, "rotation", -_POKE_ANGLE_RAD, step_sec)
	_poke_tween.tween_property(self, "rotation", 0.0, step_sec)


## One short pulse that shows this point still needs work.
func pulse() -> void:
	if is_instance_valid(_pulse_tween):
		_pulse_tween.kill()
	scale = Vector2.ONE
	_pulse_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	var half_sec := G.settings.point_pulse_sec * 0.5
	_pulse_tween.tween_property(
		self,
		"scale",
		Vector2.ONE * _PULSE_SCALE,
		half_sec,
	)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, half_sec)


## Shows or hides the idle hint outline around this point. The
## hint tracker calls it after its delay, and clears it as soon as
## the player works on the point. The outline follows the point's
## own collision shape, so every point kind highlights in place.
func set_hint_active(is_active: bool) -> void:
	_is_hint_active = is_active
	if is_active:
		var points := _get_hint_polygon()
		if points.size() < 3:
			return
		if not is_instance_valid(_hint_hint):
			_hint_hint = OutlineHint.new()
			add_child(_hint_hint)
		_hint_hint.polygon = points
		_hint_hint.set_active(true)
	elif is_instance_valid(_hint_hint):
		_hint_hint.set_active(false)


## True while the idle hint outline shows on this point.
func is_hint_active() -> bool:
	return (
		_is_hint_active
		and is_instance_valid(_hint_hint)
		and _hint_hint.is_active()
	)


func _get_hint_polygon() -> PackedVector2Array:
	for child in get_children():
		if child is CollisionShape2D:
			var points := OutlineHint.get_shape_polygon(
				child as CollisionShape2D,
			)
			if points.size() >= 3:
				return points
	var points := PackedVector2Array()
	for index in 12:
		var angle := TAU * float(index) / 12.0
		points.append(Vector2.from_angle(angle) * 22.0)
	return points


## Swaps this point for an instance of `broken_scene` with the same
## transform. Returns the new point, or null when it can't break.
func break_point() -> InteractionPoint:
	if broken_scene == null:
		return null
	var broken: InteractionPoint = broken_scene.instantiate()
	var parent := get_parent()
	parent.add_child(broken)
	parent.move_child(broken, get_index())
	broken.transform = transform
	release_tool()
	queue_free()
	return broken
