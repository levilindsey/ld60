class_name DustClump
extends DirtSpot
## A clump of dust the air blower puffs away (docs/design/
## canned_air.md). The art, its set and its color are configured on
## the shared `DirtSpot` base.


## How much dust there is. More takes more puffs and draws a
## bigger clump.
@export var amount := 1.0

## Hit points left.
var hit_points_left := 0.0

var _is_gone := false
var _wobble_tween: Tween
var _fly_tween: Tween


func _ready() -> void:
	super._ready()
	type = Type.DUST_CLUMP
	role = Role.REPAIR
	_set_up_art()
	_art_home_scale *= sqrt(maxf(amount, 0.01))
	art.scale = _art_home_scale
	hit_points_left = amount
	_update_alpha()


## Air hit the clump. `strength` runs from a third at the far end
## of the cone to full near the nozzle.
func on_sprayed(strength: float, direction: Vector2, delta: float) -> void:
	if mode == Mode.FINISHED or _is_gone:
		return
	mode = Mode.ACTIVE
	var damage := G.settings.air_blow_rate * strength * delta
	hit_points_left = maxf(hit_points_left - damage, 0.0)
	_wobble()
	if hit_points_left <= 0.0:
		_blow_off(direction)
	else:
		_update_alpha()


func on_poked() -> void:
	_wobble()
	super.on_poked()


func _blow_off(direction: Vector2) -> void:
	_is_gone = true
	G.audio.play_sound(&"whoosh")
	if is_instance_valid(_fly_tween):
		_fly_tween.kill()
	_fly_tween = create_tween()
	_fly_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_fly_tween.set_parallel()
	var target := global_position + direction * 90.0 + Vector2(0.0, -20.0)
	_fly_tween.tween_property(self, "global_position", target, 0.35)
	_fly_tween.tween_property(art, "modulate:a", 0.0, 0.35)
	_fly_tween.tween_property(art, "scale", _art_home_scale * 0.3, 0.35)
	_fly_tween.chain().tween_callback(_finish_blown_off)


func _finish_blown_off() -> void:
	art.hide()
	finish()


func _wobble() -> void:
	if is_instance_valid(_wobble_tween):
		_wobble_tween.kill()
	_wobble_tween = create_tween()
	_wobble_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var tilt := _art_home_rotation + randf_range(-0.18, 0.18)
	_wobble_tween.tween_property(art, "rotation", tilt, 0.06)
	_wobble_tween.tween_property(art, "rotation", _art_home_rotation, 0.1)


func _update_alpha() -> void:
	var fraction := 0.0
	if amount > 0.0:
		fraction = clampf(hit_points_left / amount, 0.0, 1.0)
	_set_art_alpha(0.25 + 0.75 * fraction)
