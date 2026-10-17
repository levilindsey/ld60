class_name Session
extends RefCounted


var is_game_over := true


func _init() -> void:
	reset()


func reset() -> void:
	is_game_over = true
