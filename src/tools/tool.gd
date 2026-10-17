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
const POSITION_DURATION_SEC := 0.3

@export var type := Type.FLAT_HEAD_SCREW_DRIVER

## The point on the tool that stays under the mouse cursor while held.
@export var cursor_position: Marker2D

## The clickable area for grabbing the tool.
@export var grab_area: Area2D
## The area that interactions with an InteractionPoint.
@export var interaction_area: Area2D
## The area that will align with the corresponding tool holder.
@export var holder_area: Area2D

@export var stored_rotation_deg := 0.0
@export var held_rotation_deg := 0.0

var mode := Mode.ENTERING:
	set(value):
		mode = value
		_set_mode(value)
		_update_cursor()

var _is_hovered := false

@onready var position_tween: Tween
@onready var rotation_tween: Tween


func _set_mode(to_mode: Mode) -> void:
	match to_mode:
		Mode.ENTERING, \
		Mode.STORED:
			_set_rotation(deg_to_rad(stored_rotation_deg))

			var holder_area_offset := holder_area.global_position - global_position
			var holder_position := G.level.get_tool_holder_position(type)
			_tween_position(holder_position - holder_area_offset)
		Mode.HELD:
			# The follow logic in _physics_process takes over the position.
			if is_instance_valid(position_tween):
				position_tween.kill()
			_set_rotation(deg_to_rad(held_rotation_deg))
		Mode.IN_USE:
			pass
		_:
			G.error()


func _ready() -> void:
	G.check(is_instance_valid(cursor_position))

	G.check(is_instance_valid(grab_area))
	G.check(grab_area.monitorable)
	G.check(grab_area.input_pickable)
	G.check(grab_area.collision_layer == Settings.PhysicsLayer.TOOLS)
	grab_area.input_event.connect(_on_grab_area_input_event)
	grab_area.mouse_entered.connect(_on_mouse_entered)
	grab_area.mouse_exited.connect(_on_mouse_exited)

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


func _physics_process(delta: float) -> void:
	if mode == Mode.HELD:
		# Have the tool follow the cursor when held.
		var cursor_position_offset := cursor_position.global_position - global_position
		global_position = get_global_mouse_position() - cursor_position_offset


func _set_rotation(p_rotation: float) -> void:
	if is_instance_valid(rotation_tween):
		rotation_tween.kill()
	rotation_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rotation_tween.tween_property(self, "rotation", p_rotation, ROTATE_DURATION_SEC)


func _tween_position(p_global_position: Vector2) -> void:
	if is_instance_valid(position_tween):
		position_tween.kill()
	position_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	position_tween.tween_property(self, "global_position", p_global_position, POSITION_DURATION_SEC)


func _on_grab_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		_on_clicked()


func _on_clicked() -> void:
	if mode == Mode.ENTERING or mode == Mode.STORED:
		pick_up_tool()


func _on_mouse_entered() -> void:
	_is_hovered = true
	_update_cursor()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_update_cursor()


func _update_cursor() -> void:
	# TODO: Add a grab-hand cursor.
	# TODO: Don't do this if another tool is grabbed.
	var can_grab := (
		_is_hovered
		and (mode == Mode.ENTERING or mode == Mode.STORED)
	)
	var shape := Input.CURSOR_ARROW
	if can_grab:
		shape = Input.CURSOR_POINTING_HAND
	# The default shape persists across mouse motion. A one-shot
	# DisplayServer.cursor_set_shape() is reset by the next motion event.
	Input.set_default_cursor_shape(shape)


func pick_up_tool() -> void:
	mode = Mode.HELD
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	# TODO(levilindsey): Tween the position (we'll need to add a pick-up offset, apply the offset in physics_process, and tween that offset).
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
		put_away()


func _on_holder_area_exited(holder: Area2D) -> void:
	G.check(holder is ToolHolder)
	holder.on_tool_exited(self)


func put_away() -> void:
	mode = Mode.STORED

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
