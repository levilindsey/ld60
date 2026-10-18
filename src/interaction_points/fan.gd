class_name Fan
extends InteractionPoint
## A fan the air blower spins (docs/design/canned_air.md).
##
## A healthy fan spins up fast and coasts. A dry fan has high
## friction, barely turns and squeaks. Oiling it waits for the
## oil can (LX21), so a fan never finishes here.


## The blades. They turn around the hub.
@export var art: Node2D
## How fast the spin dies away. High means dry.
@export var friction := 0.4

## The spin right now, in radians per second.
var angular_velocity := 0.0


func _ready() -> void:
	super._ready()
	type = Type.FAN
	role = Role.REPAIR
	G.check(is_instance_valid(art))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_zero_approx(angular_velocity) or not is_instance_valid(art):
		return
	art.rotation += angular_velocity * delta
	angular_velocity *= exp(-friction * delta)
	if absf(angular_velocity) < 0.01:
		angular_velocity = 0.0


## Air hit the fan. It spins up by the puff's strength.
func on_sprayed(strength: float, _direction: Vector2, delta: float) -> void:
	angular_velocity += strength * G.settings.fan_spin_gain * delta
	if is_dry():
		G.audio.play_sound(&"creak")


## True while the fan needs oil.
func is_dry() -> bool:
	return friction >= 2.0


func on_poked() -> void:
	if is_dry():
		G.audio.play_sound(&"creak")
	super.on_poked()
