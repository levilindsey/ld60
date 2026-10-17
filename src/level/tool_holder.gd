class_name ToolHolder
extends Area2D


enum Type {
	FLAT_HEAD_SCREW_DRIVER,
}

@export var type := Type.FLAT_HEAD_SCREW_DRIVER


func _ready() -> void:
	G.check(monitorable)
	G.check(collision_layer == G.settings.PhysicsLayer.TOOL_HOLDERS)


func on_tool_entered(tool: Tool) -> void:
	pass


func on_tool_exited(tool: Tool) -> void:
	pass
