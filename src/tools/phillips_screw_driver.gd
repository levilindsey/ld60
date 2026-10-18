class_name PhillipsScrewDriver
extends Tool
## The Phillips screwdriver. It borrows the flathead driver's
## art until its own lands. While IN_USE, the screw turns it
## (docs/design/phillips.md).


## The driver's art. Its x axis runs along the shaft from the tip.
@export var art: Node2D

## The angle the driver starts at on a screw.
var in_use_angle_deg := 125.0


func _ready() -> void:
	super._ready()
	G.check(is_instance_valid(art))


func _start_twist_animation() -> void:
	%AnimatedSprite2D.play("twisting")


func _stop_twist_animation() -> void:
	%AnimatedSprite2D.play("default")


func _set_mode(to_mode: Mode, from_mode: Mode) -> void:
	if to_mode == from_mode:
		return

	if from_mode == Mode.IN_USE:
		_stop_twist_animation()
	elif to_mode == Mode.IN_USE:
		_start_twist_animation()

	super._set_mode(to_mode, from_mode)

	match to_mode:
		Mode.IN_USE:
			tween_rotation(deg_to_rad(in_use_angle_deg), Tween.EASE_IN_OUT)
