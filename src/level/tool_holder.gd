class_name ToolHolder
extends Area2D
## A slot in the tool rack. A tool goes home to the holder of its type.
##
## Each holder also carries an `outline_polygon`, shaped and placed
## per holder in the editor. The polygon itself is never drawn. While
## the holder's tool is held or in use, a faint outline is drawn
## around it, so the player can see where the tool goes back.


@export var type: Tool.Type = Tool.Type.FLAT_HEAD_SCREW_DRIVER

## The shape the in-use outline follows, in this holder's local
## points. Placeholder rectangle for now; shape it per holder in
## the level scene.
@export var outline_polygon := PackedVector2Array([
	Vector2(-34.0, -42.0),
	Vector2(34.0, -42.0),
	Vector2(34.0, 42.0),
	Vector2(-34.0, 42.0),
])

## How faint the in-use outline is next to a normal outline hint.
@export_range(0.0, 1.0, 0.05) var outline_alpha_scale := 0.45

var _outline_hint: OutlineHint


func _ready() -> void:
	G.check(monitorable)
	G.check(collision_layer == Settings.PhysicsLayer.TOOL_HOLDERS)
	G.check(is_instance_valid(_get_shape()))
	_outline_hint = OutlineHint.new()
	_outline_hint.polygon = outline_polygon
	_outline_hint.alpha_scale = outline_alpha_scale
	add_child(_outline_hint)
	_outline_hint.set_active(false)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_outline_hint):
		return
	if _outline_hint.polygon != outline_polygon:
		_outline_hint.polygon = outline_polygon
	if not is_equal_approx(_outline_hint.alpha_scale, outline_alpha_scale):
		_outline_hint.alpha_scale = outline_alpha_scale
	var should_show := _is_tool_in_hand()
	if should_show != _outline_hint.is_active():
		_outline_hint.set_active(should_show)


## The center of the holder's shape, where a stored tool's holder shape
## sits.
func get_shape_position() -> Vector2:
	return _get_shape().global_position


## True while the faint outline around `outline_polygon` shows.
func is_outline_shown() -> bool:
	return is_instance_valid(_outline_hint) and _outline_hint.is_active()


## True while this holder's tool is in the hand or engaged on a point.
func _is_tool_in_hand() -> bool:
	if not is_instance_valid(G.level):
		return false
	var tool := G.level.tools_by_type.get(type) as Tool
	if not is_instance_valid(tool):
		return false
	return tool.mode == Tool.Mode.HELD or tool.mode == Tool.Mode.IN_USE


func _get_shape() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null
