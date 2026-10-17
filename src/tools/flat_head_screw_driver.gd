class_name FlatHeadScrewDriver
extends Tool
## The flathead screwdriver. While IN_USE, the screw turns it around its
## tip with each twist (docs/design/flathead.md).


## The handle's squash when it tenses before a twist: shorter along the
## shaft, a little wider across it.
const _TENSE_SCALE := Vector2(0.92, 1.05)
## Seconds the handle takes to relax after it tensed.
const _RELAX_SEC := 0.1

## The driver's art. Its x axis runs along the shaft from the tip, so the
## tense squash keeps the tip in place.
@export var art: Node2D

## The angle the driver starts at on a screw. Each twist adds to it.
var in_use_angle_deg := 125.0

var _tense_tween: Tween


func _ready() -> void:
	super._ready()
	G.check(is_instance_valid(art))


## Turns the driver with the screw: its in-use angle plus how far the
## screw has turned since the driver engaged.
func set_twist_rotation(twist_rad: float) -> void:
	# We don't want to rotate the screwdriver; we want to play the twist animation.
	pass


func _start_twist_animation() -> void:
	%AnimatedSprite2D.play("twisting")


func _stop_twist_animation() -> void:
	%AnimatedSprite2D.play("default")


## The handle tenses before a twist: a small squash, then it relaxes.
func tense(duration_sec: float) -> void:
	if is_instance_valid(_tense_tween):
		_tense_tween.kill()
	art.scale = Vector2.ONE
	_tense_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	_tense_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tense_tween.tween_property(
		art,
		"scale",
		_TENSE_SCALE,
		duration_sec,
	).set_ease(Tween.EASE_OUT)
	_tense_tween.tween_property(
		art,
		"scale",
		Vector2.ONE,
		_RELAX_SEC,
	).set_ease(Tween.EASE_IN)


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
