class_name Rag
extends Tool
## The rag (docs/design/solvent.md). There is no solvent yet, so
## it wipes dry. Press and drag over grime to clean it. The hanging
## sprite shows on the rack and the bunched sprite in the hand.


## The tall hanging rag shown while stored.
@export var hanging_sprite: Sprite2D
## The bunched rag shown while held.
@export var held_sprite: Sprite2D

var _is_wiping := false
var _last_tip_position := Vector2.ZERO
var _last_move_direction := Vector2.ZERO
var _cleaned_total := 0.0
## Distance dragged since the last wipe sound, in pixels.
var _wipe_sound_distance_px := 0.0


func _ready() -> void:
	super._ready()
	G.check(is_instance_valid(hanging_sprite))
	G.check(is_instance_valid(held_sprite))
	_show_held_art(false)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _is_wiping or delta <= 0.0:
		return
	var tip_position := get_tip_position()
	var moved := tip_position - _last_tip_position
	var distance_px := moved.length()
	_last_tip_position = tip_position
	if distance_px <= 0.0:
		return
	var speed := distance_px / delta
	var is_reversed := false
	if distance_px > 1.0:
		var direction := moved / distance_px
		if (
			not _last_move_direction.is_zero_approx()
			and direction.dot(_last_move_direction) < -0.5
		):
			is_reversed = true
		_last_move_direction = direction
	_wipe_sound_distance_px += distance_px
	if _wipe_sound_distance_px >= 48.0:
		_wipe_sound_distance_px = 0.0
		G.audio.play_sound(&"rag_wipe")
	var speed_share := clampf(
		speed / maxf(G.settings.rag_speed_cap_px_per_sec, 1.0),
		0.0,
		1.0,
	)
	var damage := G.settings.rag_wipe_rate * speed_share * delta
	if is_reversed:
		damage += G.settings.rag_reversal_bonus
	for area in interaction_area.get_overlapping_areas():
		if area is GrimeSpot:
			var spot := area as GrimeSpot
			if spot.is_exposed() and spot.is_visible_in_tree():
				spot.on_wiped(damage, delta)
				_cleaned_total += damage
				_update_dirt_tint()
		elif area is GlueSmear:
			var smear := area as GlueSmear
			if smear.is_exposed() and smear.is_visible_in_tree():
				smear.on_wiped(damage, delta)
				_cleaned_total += damage
				_update_dirt_tint()
		elif area is Surface:
			(area as Surface).on_wiped(distance_px)


func is_effect_tool() -> bool:
	return true


## A press with the rag starts a wipe where it lands.
func on_effect_pressed(_global_point: Vector2) -> void:
	_is_wiping = true
	_wipe_sound_distance_px = 0.0
	_last_tip_position = get_tip_position()
	_last_move_direction = Vector2.ZERO
	if is_instance_valid(G.level):
		G.level.hand.set_input_owner(self)
	G.audio.play_sound(&"rag_wipe")


## A finger can land anywhere, so movement counts from the press.
func on_pointer_pressed(_global_point: Vector2) -> void:
	_last_tip_position = get_tip_position()


func on_pointer_released(_global_point: Vector2) -> void:
	_stop_wiping()


func put_away() -> void:
	_stop_wiping()
	super.put_away()


func _set_mode(to_mode: Mode, from_mode: Mode) -> void:
	super._set_mode(to_mode, from_mode)
	_show_held_art(to_mode == Mode.HELD or to_mode == Mode.IN_USE)


func _show_held_art(is_held: bool) -> void:
	if is_instance_valid(hanging_sprite):
		hanging_sprite.visible = not is_held
	if is_instance_valid(held_sprite):
		held_sprite.visible = is_held


func _stop_wiping() -> void:
	_is_wiping = false
	_wipe_sound_distance_px = 0.0
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)


## The rag browns a little with everything it has cleaned.
func _update_dirt_tint() -> void:
	if not is_instance_valid(held_sprite):
		return
	var share := clampf(_cleaned_total / 3.0, 0.0, 1.0)
	held_sprite.modulate = Color.WHITE.lerp(
		Color(0.78, 0.68, 0.55),
		share,
	)
