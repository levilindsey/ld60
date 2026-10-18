class_name AirBlower
extends Tool
## The air blower bulb (docs/design/canned_air.md). A tap
## squeezes the bulb once and puffs air out of the nozzle. The
## plump sprite swaps to the squeezed one for each puff.


## Where the nozzle points, before the tool's own turn.
const _NOZZLE_DIRECTION := Vector2.DOWN

## The plump bulb, at rest.
@export var plump_sprite: Sprite2D
## The squeezed bulb, while a puff goes out.
@export var squeezed_sprite: Sprite2D
## The puff cone, shown while a puff goes out.
@export var cone_visual: Polygon2D

var _is_squeezed := false
var _squeeze_tween: Tween


func _ready() -> void:
	super._ready()
	G.check(is_instance_valid(plump_sprite))
	G.check(is_instance_valid(squeezed_sprite))
	G.check(is_instance_valid(cone_visual))
	squeezed_sprite.hide()
	cone_visual.hide()
	_build_cone()


func is_effect_tool() -> bool:
	return true


## A tap squeezes once. Holding does nothing extra.
func on_effect_pressed(_global_point: Vector2) -> void:
	if _is_squeezed:
		return
	_is_squeezed = true
	plump_sprite.hide()
	squeezed_sprite.show()
	cone_visual.show()
	cone_visual.modulate.a = 0.35
	G.audio.play_sound(&"whoosh", true)
	_puff()
	if is_instance_valid(_squeeze_tween):
		_squeeze_tween.kill()
	_squeeze_tween = create_tween()
	_squeeze_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_squeeze_tween.tween_interval(G.settings.air_squeeze_sec)
	_squeeze_tween.tween_callback(_release_squeeze)


## The world direction the nozzle points right now.
func get_nozzle_direction() -> Vector2:
	return _NOZZLE_DIRECTION.rotated(global_rotation)


## Where the nozzle is in the world. The puff and its drawn cone
## both start here, at the interaction area.
func get_nozzle_position() -> Vector2:
	return interaction_area.global_position


func _puff() -> void:
	if not is_instance_valid(G.level):
		return
	var item := G.level.active_repairable
	if not is_instance_valid(item):
		return
	var nozzle := get_nozzle_position()
	var direction := get_nozzle_direction()
	var length := G.settings.air_cone_length_px
	var half_angle := deg_to_rad(G.settings.air_cone_half_angle_deg)
	for layer in item.layers:
		for point in layer.get_points():
			if not (point is DustClump or point is Fan):
				continue
			if not point.is_exposed() or not point.is_visible_in_tree():
				continue
			var offset := point.global_position - nozzle
			var distance := offset.length()
			if distance > length:
				continue
			var strength := 1.0
			if distance > 1.0:
				if absf(offset.angle_to(direction)) > half_angle:
					continue
				strength = lerpf(1.0, 1.0 / 3.0, distance / length)
			if point is DustClump:
				(point as DustClump).on_sprayed(
					strength, direction, G.settings.air_puff_sec
				)
			else:
				(point as Fan).on_sprayed(
					strength, direction, G.settings.air_puff_sec
				)


func _release_squeeze() -> void:
	_is_squeezed = false
	squeezed_sprite.hide()
	plump_sprite.show()
	cone_visual.hide()


func _build_cone() -> void:
	var direction := _NOZZLE_DIRECTION
	var length := G.settings.air_cone_length_px
	var spread := tan(deg_to_rad(G.settings.air_cone_half_angle_deg))
	var end := direction * length
	var side := direction.orthogonal() * spread * length
	cone_visual.polygon = PackedVector2Array(
		[Vector2.ZERO, end + side, end - side]
	)
	cone_visual.position = to_local(interaction_area.global_position)
