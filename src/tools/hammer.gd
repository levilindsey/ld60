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

## The hammer art. It turns around the striking face.
@export var art: Node2D

## The charge of the current wind up, from 0 to 1.
var charge := 0.0

var _phase := WindPhase.READY
var _wind_sec := 0.0
var _locked_point := Vector2.ZERO
var _locked_target: StrikablePoint
var _locked_surface: Surface
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
	if charge >= 1.0:
		# The held full swing trembles.
		art.position = Vector2(
			randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)
		)
	else:
		art.position = Vector2.ZERO
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


## True while the charge sits inside the locked target's band.
func is_charge_in_band() -> bool:
	return (
		is_instance_valid(_locked_target)
		and charge >= _locked_target.band_min
		and charge <= _locked_target.band_max
	)


func is_effect_tool() -> bool:
	return true


## A press locks the strike point and starts the wind up.
func on_effect_pressed(global_point: Vector2) -> void:
	if _phase != WindPhase.READY:
		return
	_locked_point = global_point
	_locked_target = null
	_locked_surface = null
	if is_instance_valid(G.level):
		var point := G.level.hand.find_point(global_point)
		_locked_target = point as StrikablePoint
		if not is_instance_valid(_locked_target):
			_locked_surface = G.level.hand.find_surface(global_point)
		G.level.hand.set_input_owner(self)
	_phase = WindPhase.WINDING
	_wind_sec = 0.0
	charge = 0.0
	queue_redraw()


func on_pointer_released(_global_point: Vector2) -> void:
	if _phase == WindPhase.WINDING:
		_swing()


func put_away() -> void:
	_cancel_swing()
	super.put_away()


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
	if is_instance_valid(_locked_target):
		_locked_target.on_struck(charge)
	elif is_instance_valid(_locked_surface):
		_locked_surface.on_struck(_locked_point, charge)
		if charge >= G.settings.hammer_surface_damage_charge:
			G.audio.play_sound(&"thud", true)
			G.level.shake_camera(5.0, 0.15)
		else:
			G.audio.play_sound(&"click")
	else:
		G.audio.play_sound(&"thud", true)
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
