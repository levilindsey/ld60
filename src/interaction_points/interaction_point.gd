extends Area2D
class_name InteractionPoint


enum Type {
	FLAT_HEAD_SCREW,
}

enum Mode {
	UNSTARTED,
	ACTIVE,
	FINISHED,
}

@export var type := Type.FLAT_HEAD_SCREW

var mode := Mode.UNSTARTED


func _ready() -> void:
	G.check(monitorable)
	G.check(collision_layer == G.settings.PhysicsLayer.INTERACTION_POINTS)


func on_tool_entered(tool: Tool) -> void:
	pass


func on_tool_exited(tool: Tool) -> void:
	pass
