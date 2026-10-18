class_name DustClump
extends InteractionPoint
## A clump of dust the air blower puffs away (docs/design/
## canned_air.md). The dust sprite lands with LX24. Until then
## the scene draws a placeholder blob.


## The dust art. It fades as the clump thins.
@export var art: CanvasItem
## Hit points the clump starts with.
@export var hit_points := 1.0

## Hit points left.
var hit_points_left := 0.0

var _is_gone := false
var _wobble_tween: Tween
var _fly_tween: Tween


func _ready() -> void:
	super._ready()
	type = Type.DUST_CLUMP
	role = Role.REPAIR
	G.check(is_instance_valid(art))
	hit_points_left = hit_points
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
	_fly_tween.tween_property(art, "scale", Vector2.ONE * 0.3, 0.35)
	_fly_tween.chain().tween_callback(_finish_blown_off)


func _finish_blown_off() -> void:
	art.hide()
	finish()


func _wobble() -> void:
	if is_instance_valid(_wobble_tween):
		_wobble_tween.kill()
	_wobble_tween = create_tween()
	_wobble_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var tilt := randf_range(-0.18, 0.18)
	_wobble_tween.tween_property(art, "rotation", tilt, 0.06)
	_wobble_tween.tween_property(art, "rotation", 0.0, 0.1)


func _update_alpha() -> void:
	if not is_instance_valid(art):
		return
	var fraction := 0.0
	if hit_points > 0.0:
		fraction = clampf(hit_points_left / hit_points, 0.0, 1.0)
	art.modulate.a = 0.25 + 0.75 * fraction
