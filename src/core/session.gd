class_name Session
extends RefCounted


var is_game_over := true
## Items that left through the outbox finished.
var fixed_item_count := 0


func _init() -> void:
	reset()


func reset() -> void:
	is_game_over = true
	fixed_item_count = 0
