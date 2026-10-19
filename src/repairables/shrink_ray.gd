class_name ShrinkRay
extends Repairable
## A raygun from the pawn shop.
##
## The first hammer hit anywhere on it sets it off: the ray pulses,
## its broken crystal flares blue and swells, and the blast shrinks
## the hammer for good (`Hammer.shrink()`). After that, the jammed
## spot (`%Jam`) takes a few tiny-hammer hits, the grime on the crystal
## wipes off, the cracked crystal gets replaced, and the broken
## trigger gets glued back on.


## The blast pulse: the ray dips small, then swells, then settles.
const _PULSE_SMALL := 0.92
const _PULSE_BIG := 1.05
const _PULSE_SMALL_SEC := 0.09
const _PULSE_BIG_SEC := 0.13
const _PULSE_SETTLE_SEC := 0.16
## The broken crystal swells and dips with the blast, tinted blue.
const _CRYSTAL_BIG := 1.4
const _CRYSTAL_SMALL := 0.82
const _CRYSTAL_BLUE := Color(0.62, 0.8, 1.25)


## True once the ray has gone off.
var has_fired := false

var _home_scale := Vector2.ONE


func _ready() -> void:
	super()
	%Jam.visible = false
	_home_scale = scale
	# The crystal stays seated until the blast shakes it loose.
	%Crystal.is_sealed = true
	add_to_group(Hammer.STRIKABLE_PROPS_GROUP)


## True for a hammer press on the ray's drawing before it has gone off.
func is_struck_at(global_point: Vector2) -> bool:
	var art := layers[0].art as Sprite2D
	return (
		not has_fired
		and mode == Mode.UNDER_REPAIR
		and art.is_pixel_opaque(art.to_local(global_point))
	)


## The hammer set it off: the ray pulses, its crystal flares, the
## blast shrinks the hammer, and the jammed spot shows up.
func on_struck(_charge: float) -> void:
	has_fired = true
	%Jam.visible = true
	%Crystal.is_sealed = false
	G.audio.play_sound(&"thud", true)
	G.audio.play_sound(&"blast", true)
	G.level.shake_camera(8.0, 0.25)
	_pulse_blast()
	var hammer := G.level.hand.get_held_tool() as Hammer
	if is_instance_valid(hammer):
		hammer.shrink()


## The blast, conveyed by the ray itself: it dips small, swells
## big and settles, while the broken crystal swells, dips and
## settles with it, flaring blue for the duration.
func _pulse_blast() -> void:
	var ray_tween := create_tween()
	ray_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	ray_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ray_tween.tween_property(
		self, "scale", _home_scale * _PULSE_SMALL, _PULSE_SMALL_SEC
	)
	ray_tween.tween_property(
		self, "scale", _home_scale * _PULSE_BIG, _PULSE_BIG_SEC
	)
	ray_tween.tween_property(
		self, "scale", _home_scale, _PULSE_SETTLE_SEC
	)
	var crystal := (
		%Crystal.get_node("BrokenPart/BustedCrystal") as Sprite2D
	)
	if not is_instance_valid(crystal):
		return
	var crystal_home_scale: Vector2 = crystal.scale
	var crystal_tween := create_tween()
	crystal_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	crystal_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	crystal_tween.tween_property(
		crystal,
		"scale",
		crystal_home_scale * _CRYSTAL_BIG,
		_PULSE_SMALL_SEC + _PULSE_BIG_SEC,
	)
	crystal_tween.tween_property(
		crystal,
		"scale",
		crystal_home_scale * _CRYSTAL_SMALL,
		_PULSE_SETTLE_SEC,
	)
	crystal_tween.tween_property(
		crystal, "scale", crystal_home_scale, _PULSE_SETTLE_SEC
	)
	var tint_tween := create_tween()
	tint_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tint_tween.tween_property(
		crystal,
		"modulate",
		_CRYSTAL_BLUE,
		_PULSE_SMALL_SEC + _PULSE_BIG_SEC,
	)
	tint_tween.tween_property(
		crystal,
		"modulate",
		Color.WHITE,
		_PULSE_SETTLE_SEC * 2.0,
	)
