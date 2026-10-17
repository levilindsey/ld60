class_name ToolHolder
extends Area2D
## A slot in the tool rack. A tool goes home to the holder of its type.


@export var type: Tool.Type = Tool.Type.FLAT_HEAD_SCREW_DRIVER


func _ready() -> void:
	G.check(monitorable)
	G.check(collision_layer == Settings.PhysicsLayer.TOOL_HOLDERS)
	G.check(is_instance_valid(_get_shape()))


## The center of the holder's shape, where a stored tool's holder shape
## sits.
func get_shape_position() -> Vector2:
	return _get_shape().global_position


func _get_shape() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null
