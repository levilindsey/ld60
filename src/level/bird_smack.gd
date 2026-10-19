class_name BirdSmack
extends Node2D
## The bird hitting the window. `play_smack()` shows it and
## plays the fly animation; when that finishes the sprite falls
## (ease-in) to the `fall_to` marker, then the bird hides and
## resets, ready to be cleaned up after. `finished` fires once
## the whole beat is over.


signal finished

@export var fall_to: Marker2D

const FALL_DURATION_SEC := 0.8

var _is_playing := false
var _fall_tween: Tween


func _ready() -> void:
	hide()
	_get_sprite().animation_finished.connect(_on_fly_finished)


## Shows the bird at the glass and plays the fly animation.
func play_smack() -> void:
	if is_instance_valid(_fall_tween):
		_fall_tween.kill()
	_get_sprite().position = Vector2.ZERO
	_is_playing = true
	show()
	_get_sprite().play(&"fly")


func _on_fly_finished() -> void:
	if not _is_playing:
		return
	if not is_instance_valid(fall_to):
		_cleanup()
		return
	_fall_tween = create_tween()
	_fall_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_fall_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tween.tween_property(
		_get_sprite(),
		"position",
		to_local(fall_to.global_position),
		FALL_DURATION_SEC,
	)
	_fall_tween.tween_callback(_cleanup)


## Hides the bird and puts the sprite back at the glass, so the
## next play starts clean.
func _cleanup() -> void:
	_is_playing = false
	hide()
	_get_sprite().position = Vector2.ZERO
	finished.emit()


func _get_sprite() -> AnimatedSprite2D:
	return get_node("AnimatedSprite2D") as AnimatedSprite2D
