class_name Tool
extends Node2D


enum Type {
	FLAT_HEAD_SCREW_DRIVER,
}

enum Mode {
	ENTERING,
	STORED,
	HELD,
	IN_USE,
}

const ROTATE_DURATION_SEC := 0.3

@export var type := Type.FLAT_HEAD_SCREW_DRIVER

## The clickable area for grabbing the tool.
@export var grab_area: Area2D
## The area that interactions with an InteractionPoint.
@export var interaction_area: Area2D
## The area that will align with the corresponding tool holder.
@export var holder_area: Area2D

@export var stored_rotation := 0.0
@export var held_rotation := 0.0

var mode := Mode.ENTERING:
	set(value):
		_set_mode(value)

@onready var _rotation_tween: Tween


func _set_mode(to_mode: Mode) -> void:
	match to_mode:
		Mode.ENTERING, \
		Mode.STORED:
			_set_rotation(stored_rotation)
		Mode.HELD:
			_set_rotation(stored_rotation)
		Mode.IN_USE:
			pass
		_:
			G.error()


func _ready() -> void:
	G.check(is_instance_valid(grab_area))
	G.check(grab_area.monitorable)
	G.check(grab_area.input_pickable)
	G.check(grab_area.collision_layer == Settings.PhysicsLayer.TOOLS)
	grab_area.input_event.connect(_on_grab_area_input_event)

	G.check(is_instance_valid(interaction_area))
	G.check(interaction_area.monitoring)
	G.check(interaction_area.collision_mask == Settings.PhysicsLayer.INTERACTION_POINTS)
	interaction_area.area_entered.connect(_on_interaction_point_entered)
	interaction_area.area_exited.connect(_on_interaction_point_exited)

	G.check(is_instance_valid(holder_area))
	G.check(holder_area.monitoring)
	G.check(holder_area.collision_mask == Settings.PhysicsLayer.TOOL_HOLDERS)
	holder_area.area_entered.connect(_on_holder_area_entered)
	holder_area.area_exited.connect(_on_holder_area_exited)


func _set_rotation(p_rotation: float) -> void:
	if is_instance_valid(_rotation_tween):
		_rotation_tween.kill()
	_rotation_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_rotation_tween.tween_property(self, "rotation", p_rotation, ROTATE_DURATION_SEC)


func _on_grab_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		_on_clicked()


func _on_clicked() -> void:
	if mode == Mode.ENTERING or mode == Mode.STORED:
		_pick_up_tool()


func _pick_up_tool() -> void:
	_set_mode(Mode.HELD)
	# TODO(levilindsey): Tween the position and rotation.
	# TODO(levilindsey): Hide the cursor. Have the tool follow the cursor.
	# TODO(levilindsey): Show a grab hand cursor when hovering over tools and nothing is held.


func _on_interaction_point_entered(interaction_point: Area2D) -> void:
	G.check(interaction_point is InteractionPoint)
	interaction_point.on_tool_entered(self)


func _on_interaction_point_exited(interaction_point: Area2D) -> void:
	G.check(interaction_point is InteractionPoint)
	interaction_point.on_tool_exited(self)


func _on_holder_area_entered(holder: Area2D) -> void:
	G.check(holder is ToolHolder)
	holder.on_tool_entered(self)

	if holder.type == type and (mode == Mode.ENTERING or mode == Mode.HELD):
		_put_tool_away()


func _on_holder_area_exited(holder: Area2D) -> void:
	G.check(holder is ToolHolder)
	holder.on_tool_exited(self)


func _put_tool_away() -> void:
	_set_mode(Mode.STORED)
	# TODO(levilindsey): Tween the position and rotation.
	# TODO(levilindsey): Show the cursor.
