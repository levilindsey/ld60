class_name Hammer
extends Tool
## The hammer (docs/design/hammer.md). Press to lock the strike
## point and wind up. The ring fills with the charge. Release to
## swing. There are no nails. It jogs, realigns and reseats.


enum WindPhase {
	READY,
	WINDING,
	SWINGING,
	HOLDING,
	RECOILING,
}

## Props outside the item that the hammer can hit, like the radio. Each
## needs `is_struck_at(global_point) -> bool` and `on_struck(charge)`.
const STRIKABLE_PROPS_GROUP := &"strikable_props"
## How far the hammer jitters at full charge, in pixels each
## way. It jitters through the whole wind up, the amplitude
## rising with the charge from nothing to this.
const MAX_TREMBLE_PX := 18.0
## The shrunken hammer's size, as a share of its own.
const _TINY_SCALE := 0.4
const _SHRINK_SEC := 0.35
## How much higher the shrunken hammer's hits sound.
const _TINY_PITCH_SCALE := 1.8

## The hammer art. It turns around the striking face.
@export var art: Node2D

## The charge of the current wind up, from 0 to 1.
var charge := 0.0
## True once the shrink ray has shrunk the hammer. Its hits sound higher
## and never dent.
var is_tiny := false

var _phase := WindPhase.READY
var _wind_sec := 0.0
var _locked_point := Vector2.ZERO
var _locked_target: StrikablePoint
var _locked_surface: Surface
var _locked_layer: RepairLayer
var _locked_prop: Node2D
var _art_home_rotation := 0.0
var _swing_tween: Tween


func _ready() -> void:
	super._ready()
	G.check(is_instance_valid(art))
	_art_home_rotation = art.rotation


func _physics_process(delta: float) -> void:
	if _phase == WindPhase.READY:
		super._physics_process(delta)
	if _phase != WindPhase.WINDING:
		return
	_wind_sec += delta
	var share := clampf(_wind_sec / G.settings.hammer_charge_sec, 0.0, 1.0)
	charge = smoothstep(0.0, 1.0, share)
	var windup := deg_to_rad(G.settings.hammer_max_windup_deg) * charge
	art.rotation = _art_home_rotation + windup
	art.scale = Vector2.ONE * (1.0 + 0.15 * charge)
	# The jitter runs the whole wind up, growing with the
	# charge: still at the start, shaking hard at full.
	var tremble := MAX_TREMBLE_PX * charge
	art.position = Vector2(
		randf_range(-tremble, tremble),
		randf_range(-tremble, tremble),
	)
	queue_redraw()


## True while a swing winds up. The reticle draws then.
func is_winding() -> bool:
	return _phase == WindPhase.WINDING


## The point locked by the current wind up, or null.
func get_locked_target() -> StrikablePoint:
	return _locked_target


## The surface locked by the current wind up, or null.
func get_locked_surface() -> Surface:
	return _locked_surface


## The layer locked by the current wind up where no surface
## covers the strike point, or null. Its art takes the hit.
func get_locked_layer() -> RepairLayer:
	return _locked_layer


## The prop locked by the current wind up, or null.
func get_locked_prop() -> Node2D:
	return _locked_prop


## True while the locked prop takes the green band treatment:
## the wonky radio is fixed by a bonk at any charge, so its
## whole ring counts as the band.
func is_locked_prop_green() -> bool:
	return (
		is_instance_valid(_locked_prop)
		and _locked_prop is Radio
		and (_locked_prop as Radio).is_glitching
	)


## True while the charge sits inside the locked target's band.
func is_charge_in_band() -> bool:
	return (
		is_instance_valid(_locked_target)
		and charge >= _locked_target.band_min
		and charge <= _locked_target.band_max
	)


func is_effect_tool() -> bool:
	return true


## A press locks the strike point and starts the wind up. The
## strike point is the hammer's working end, not the cursor: the
## smack lands where the face is when the press triggers.
func on_effect_pressed(_global_point: Vector2) -> void:
	if _phase != WindPhase.READY:
		return
	_locked_point = get_work_end_position()
	_locked_target = null
	_locked_surface = null
	_locked_layer = null
	_locked_prop = null
	if is_instance_valid(G.level):
		_locked_target = _find_area_target()
		if not is_instance_valid(_locked_target):
			var point := G.level.hand.find_point(_locked_point)
			_locked_target = point as StrikablePoint
		if not is_instance_valid(_locked_target):
			_locked_target = _find_shape_target(_locked_point)
		if not is_instance_valid(_locked_target):
			_locked_surface = G.level.hand.find_surface(_locked_point)
		if not is_instance_valid(_locked_target):
			if not is_instance_valid(_locked_surface):
				_locked_layer = _find_layer_target(_locked_point)
			if not is_instance_valid(_locked_layer):
				_locked_prop = _find_strikable_prop(_locked_point)
		G.level.hand.set_input_owner(self)
	_phase = WindPhase.WINDING
	_wind_sec = 0.0
	charge = 0.0
	queue_redraw()


## The strikable point the hammer's face overlaps, or null.
## The face only has to cross the point's area; its centre
## need not land on it. Where the face crosses more than one
## point, the nearest to the face's centre wins.
func _find_area_target() -> StrikablePoint:
	var shape_node := get_interaction_shape()
	if not is_instance_valid(shape_node):
		return null
	if not is_instance_valid(shape_node.shape):
		return null
	var parameters := PhysicsShapeQueryParameters2D.new()
	parameters.shape = shape_node.shape
	parameters.transform = shape_node.global_transform
	parameters.collision_mask = (
		Settings.PhysicsLayer.INTERACTION_POINTS
	)
	parameters.collide_with_areas = true
	parameters.collide_with_bodies = false
	var space := get_world_2d().direct_space_state
	var nearest: StrikablePoint = null
	var nearest_distance := INF
	for result in space.intersect_shape(parameters, 32):
		var point := result.collider as StrikablePoint
		if (
			not is_instance_valid(point)
			or not point.is_exposed()
			or not point.is_visible_in_tree()
			or point.mode == InteractionPoint.Mode.FINISHED
		):
			continue
		var distance := shape_node.global_position.distance_squared_to(
			point.global_position
		)
		if distance < nearest_distance:
			nearest = point
			nearest_distance = distance
	return nearest


## A whack anywhere on the item's Shape counts as a whack
## on its stuck part (the TV's final whack: the whole set is
## whackable, not just one circle on it). Only a plain
## StuckPart qualifies, and only while it is unfinished and
## on the exposed layer: a bent part still has to be hit on
## the part itself.
func _find_shape_target(global_point: Vector2) -> StrikablePoint:
	if not is_instance_valid(G.level):
		return null
	var item := G.level.active_repairable
	if not is_instance_valid(item):
		return null
	if not item.is_point_in_shape(global_point):
		return null
	for layer in item.layers:
		for layer_point in layer.get_points():
			if (
				layer_point is StuckPart
				and layer_point.mode != InteractionPoint.Mode.FINISHED
				and layer_point.is_exposed()
			):
				return layer_point as StrikablePoint
	return null


## The exposed layer whose art is under a world position, or
## null. Where a piece has no Surface there, its art still
## takes a hammer hit (and a glue smear).
func _find_layer_target(global_point: Vector2) -> RepairLayer:
	if not is_instance_valid(G.level):
		return null
	var item := G.level.active_repairable
	if not is_instance_valid(item):
		return null
	for layer in item.layers:
		if layer.is_exposed() and layer.has_point(global_point):
			return layer
	return null


func on_pointer_released(_global_point: Vector2) -> void:
	if _phase == WindPhase.WINDING:
		_swing()


func put_away() -> void:
	_cancel_swing()
	super.put_away()


## Shrinks the hammer for good.
func shrink() -> void:
	if is_tiny:
		return
	is_tiny = true
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		%Wrapper,
		"scale",
		%Wrapper.scale * _TINY_SCALE,
		_SHRINK_SEC,
	)


func _swing() -> void:
	_phase = WindPhase.SWINGING
	queue_redraw()
	if is_instance_valid(_swing_tween):
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_swing_tween.tween_property(
		art,
		"rotation",
		_art_home_rotation - deg_to_rad(8.0),
		G.settings.hammer_swing_sec,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.tween_callback(_strike)


func _strike() -> void:
	# The smack lands where the working end is as the swing lands.
	_locked_point = get_work_end_position()
	if is_tiny:
		G.audio.sound_pitch_scale = _TINY_PITCH_SCALE
	if is_instance_valid(_locked_target):
		# A tiny hit can still work, but never too hard.
		var strength := charge
		if is_tiny:
			strength = minf(charge, _locked_target.band_max)
		_locked_target.on_struck(strength)
	elif is_instance_valid(_locked_surface):
		var strength := 0.0 if is_tiny else charge
		_locked_surface.on_struck(_locked_point, strength)
		if strength >= G.settings.hammer_surface_damage_charge:
			G.audio.play_sound(&"hammer_whack_heavy", true)
			G.level.shake_camera(5.0, 0.15)
		else:
			G.audio.play_sound(&"hammer_whack_light")
	elif is_instance_valid(_locked_layer):
		var strength := 0.0 if is_tiny else charge
		_locked_layer.on_struck(_locked_point, strength)
		if strength >= G.settings.hammer_surface_damage_charge:
			G.audio.play_sound(&"hammer_whack_heavy", true)
			G.level.shake_camera(5.0, 0.15)
		else:
			G.audio.play_sound(&"hammer_whack_light")
	elif is_instance_valid(_locked_prop):
		_locked_prop.on_struck(charge)
	else:
		G.audio.play_sound(&"hammer_wood", true)
	G.audio.sound_pitch_scale = 1.0
	_phase = WindPhase.HOLDING
	if is_instance_valid(_swing_tween):
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_swing_tween.tween_interval(G.settings.hammer_hit_stop_sec)
	_swing_tween.tween_callback(_recoil)


func _recoil() -> void:
	_phase = WindPhase.RECOILING
	if is_instance_valid(_swing_tween):
		_swing_tween.kill()
	_swing_tween = create_tween().set_parallel()
	_swing_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(
		art, "rotation", _art_home_rotation, G.settings.hammer_recoil_sec
	)
	_swing_tween.tween_property(
		art, "scale", Vector2.ONE, G.settings.hammer_recoil_sec
	)
	_swing_tween.tween_property(
		art, "position", Vector2.ZERO, G.settings.hammer_recoil_sec
	)
	_swing_tween.chain().tween_callback(_finish_swing)


func _finish_swing() -> void:
	_phase = WindPhase.READY
	charge = 0.0
	_locked_target = null
	_locked_surface = null
	_locked_layer = null
	_locked_prop = null
	queue_redraw()
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)
		ease_follow_offset_from(
			get_tip_position() - G.level.hand.pointer_position
		)


func _cancel_swing() -> void:
	if is_instance_valid(_swing_tween):
		_swing_tween.kill()
	_phase = WindPhase.READY
	charge = 0.0
	if is_instance_valid(art):
		art.rotation = _art_home_rotation
		art.scale = Vector2.ONE
		art.position = Vector2.ZERO
	queue_redraw()
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)


func _find_strikable_prop(global_point: Vector2) -> Node2D:
	for prop in get_tree().get_nodes_in_group(STRIKABLE_PROPS_GROUP):
		if prop.is_struck_at(global_point):
			return prop
	return null
