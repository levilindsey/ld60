class_name DustClump
extends DirtSpot
## A clump of dust the air blower puffs away (docs/design/
## canned_air.md). The art, its set and its color are configured on
## the shared `DirtSpot` base.


## Ghost copies of the clump's art shed on each puff: they
## swell up and fade out where they sit. Blown dust is not
## displaced any more; it shrinks and fades in place. This
## is the whole dust-blow effect; a shader cloud would fight
## the hand-drawn decals.
const _PUFF_GROUP := &"dust_puff"
const _BURST_PUFF_COUNT := 5
const _PUFF_MIN_SEC := 0.45
const _PUFF_MAX_SEC := 0.7

## How many decals the clump renders. It reads as more dust,
## but it does not change how much air the clump takes.
@export var amount := 1.0
## How much air the clump takes to blow away. The time it
## takes is its toughness alone.
@export var toughness := 1.0

## Hit points left.
var hit_points_left := 0.0

var _is_gone := false
var _wobble_tween: Tween
var _fly_tween: Tween


func _ready() -> void:
	super._ready()
	type = Type.DUST_CLUMP
	role = Role.REPAIR
	# Dust decals render at twice the configured size.
	_decal_size_scale = 2.0
	_set_up_art()
	_add_extra_decals(maxi(1, int(round(amount))))
	hit_points_left = maxf(toughness, 0.0)
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
	_spawn_puff(direction, 0.55)
	if get_remaining_share() <= G.settings.dust_clean_share:
		# Down to a whisper of the clump: counts as cleaned.
		hit_points_left = 0.0
		_blow_off(direction)
	else:
		_update_alpha()


## How much of the clump is left, as a share of the
## toughness it started with.
func get_remaining_share() -> float:
	return clampf(
		hit_points_left / maxf(toughness, 0.001), 0.0, 1.0
	)


func on_poked() -> void:
	_wobble()
	super.on_poked()


## Sheds `count` ghost copies of the clump's art into the
## level. Each swells to up to twice its size where it sits,
## turns a little and fades away, then frees itself.
## `alpha_scale` dims the shed wisps against the burst when
## the clump goes.
func _spawn_puff(_direction: Vector2, alpha_scale: float) -> void:
	if not is_instance_valid(G.level) or not is_instance_valid(art):
		return
	for _index in _BURST_PUFF_COUNT if alpha_scale >= 1.0 else 1:
		var ghost := Sprite2D.new()
		ghost.texture = art.texture
		ghost.region_enabled = art.region_enabled
		ghost.region_rect = art.region_rect
		ghost.centered = art.centered
		ghost.offset = art.offset
		ghost.flip_h = art.flip_h
		ghost.flip_v = art.flip_v
		# Normal blending: the source art's multiply decal
		# material would darken whatever bench it crosses.
		ghost.material = null
		ghost.modulate = Color(
			art.modulate.r,
			art.modulate.g,
			art.modulate.b,
			art.modulate.a * 0.55 * alpha_scale,
		)
		ghost.global_position = global_position
		ghost.rotation = art.rotation + randf_range(-0.4, 0.4)
		var start_scale := _art_home_scale * randf_range(0.5, 0.8)
		ghost.scale = start_scale
		ghost.z_index = 18
		ghost.z_as_relative = false
		ghost.add_to_group(_PUFF_GROUP)
		G.level.add_child(ghost)
		var duration := randf_range(_PUFF_MIN_SEC, _PUFF_MAX_SEC)
		var tween := ghost.create_tween()
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.set_parallel()
		tween.tween_property(
			ghost,
			"scale",
			start_scale * randf_range(1.7, 2.3),
			duration,
		)
		tween.tween_property(
			ghost,
			"rotation",
			ghost.rotation + randf_range(-0.7, 0.7),
			duration,
		)
		tween.tween_property(ghost, "modulate:a", 0.0, duration)
		tween.chain().tween_callback(ghost.queue_free)


func _blow_off(direction: Vector2) -> void:
	_is_gone = true
	_spawn_puff(direction, 1.0)
	G.audio.play_sound(&"whoosh")
	if is_instance_valid(_fly_tween):
		_fly_tween.kill()
	_fly_tween = create_tween()
	_fly_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_fly_tween.set_parallel()
	# The clump stays where it sits and shrinks and fades
	# away; blown dust is not displaced any more.
	# Every decal goes, not just the art: the extras are most
	# of the patch when Amount is high, and leaving them drawn
	# kept the dust looking present after it had blown off.
	for decal in _decal_sprites:
		if not is_instance_valid(decal):
			continue
		_fly_tween.tween_property(decal, "modulate:a", 0.0, 0.35)
		_fly_tween.tween_property(
			decal, "scale", decal.scale * 0.3, 0.35
		)
	_fly_tween.chain().tween_callback(_finish_blown_off)


func _finish_blown_off() -> void:
	for decal in _decal_sprites:
		if is_instance_valid(decal):
			decal.hide()
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
	if toughness > 0.0:
		fraction = clampf(hit_points_left / toughness, 0.0, 1.0)
	_set_art_alpha(0.25 + 0.75 * fraction)
