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


## Whether the twisting animation is playing. It only plays
## while the engaged screw is actually making progress.
var _is_twist_animation_active := false


## Starts the twisting animation while the screw makes progress
## and returns to the still art when it stops.
func set_twist_animation_active(is_active: bool) -> void:
	if _is_twist_animation_active == is_active:
		return
	_is_twist_animation_active = is_active
	if is_active:
		%AnimatedSprite2D.play("twisting")
	else:
		%AnimatedSprite2D.play("default")


func _set_mode(to_mode: Mode, from_mode: Mode) -> void:
	if to_mode == from_mode:
		return

	if from_mode == Mode.IN_USE:
		set_twist_animation_active(false)

	super._set_mode(to_mode, from_mode)

	match to_mode:
		Mode.IN_USE:
			tween_rotation(deg_to_rad(in_use_angle_deg), Tween.EASE_IN_OUT)
