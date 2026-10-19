class_name BrokenPoint
extends InteractionPoint
## A spot where a piece broke off (docs/design/glue.md). Glue
## must be applied here first. Then the matching BrokenPiece is
## dragged over it and held still: a drifting dot must stay
## inside a ring while a timer fills. Leaving the ring fails
## the attempt, but the glue stays.

## How close the glue nozzle has to land, in world pixels.
const _GLUE_HIT_RADIUS_PX := 30.0
## Draw order of the hold game while it runs, over the tools
## (z 20) and every loose piece, in absolute canvas order.
const _HOLD_Z_INDEX := 40

## Seconds the piece must be held still. Per point, so one
## item can ask for a quick tack and another for a long hold.
@export var hold_sec := 5.0

## True once glue has been squeezed onto this point. It
## survives a failed hold, so the player only glues once.
var has_glue := false
## True while the matching piece is being held over the point.
var is_holding := false
## Still seconds banked in the current hold, from 0 upward.
var hold_progress_sec := 0.0
## The piece that belongs here. Its own target export sets it.
var piece: BrokenPiece
## The glue decal on the layer's art, once glue lands here.
var glue_decal: Sprite2D

var _dot_drift := Vector2.ZERO
var _dot_drift_velocity := Vector2.ZERO
var _drift_retarget_left_sec := 0.0
var _home_z_index := 0
var _home_z_as_relative := true


func _ready() -> void:
	super._ready()
	type = Type.BROKEN_POINT
	role = Role.REPAIR
	accepted_tools = [Tool.Type.GLUE]
	_home_z_index = z_index
	_home_z_as_relative = z_as_relative


func _process(_delta: float) -> void:
	if is_holding or has_glue or mode == Mode.FINISHED:
		queue_redraw()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if mode == Mode.FINISHED or delta <= 0.0:
		return
	if not is_holding:
		_try_start_hold()
		return
	_step_hold(delta)


func _draw() -> void:
	# The scar the piece left behind.
	var scar := Color(0.12, 0.1, 0.1, 0.9)
	draw_line(Vector2(-14, -10), Vector2(12, 8), scar, 3.0, true)
	draw_line(Vector2(-8, 12), Vector2(14, -8), scar, 3.0, true)
	draw_arc(
		Vector2.ZERO, 18.0, 0.0, TAU, 24, scar, 2.0, true
	)
	if mode == Mode.FINISHED:
		draw_arc(
			Vector2.ZERO,
			18.0,
			0.0,
			TAU,
			24,
			Color(0.45, 0.95, 0.5, 0.95),
			3.0,
			true,
		)
		return
	if not is_holding:
		return
	var inner := G.settings.broken_hold_inner_radius_px
	var outer := G.settings.broken_hold_outer_radius_px
	var dot_radius := G.settings.broken_hold_dot_radius_px
	var state := get_hold_state()
	var band_color := Color(0.45, 0.95, 0.5, 0.9)
	if state == 1:
		band_color = Color(1.0, 0.75, 0.25, 0.95)
	elif state == 2:
		band_color = Color(1.0, 0.3, 0.25, 0.95)
	# The wide band the dot has to stay inside, and its safe
	# core. The ring floats above the point, clear of the
	# finger holding the piece on it.
	var ring := _get_ring_center()
	draw_arc(ring, outer, 0.0, TAU, 40, band_color, 5.0, true)
	draw_arc(ring, inner, 0.0, TAU, 32, band_color, 2.0, true)
	draw_circle(ring, inner, Color(band_color, 0.12))
	draw_line(
		Vector2.ZERO, ring, Color(band_color, 0.35), 2.0, true
	)
	# Progress around the outside while the dot stays good.
	if hold_sec > 0.0:
		var share := clampf(hold_progress_sec / hold_sec, 0.0, 1.0)
		draw_arc(
			ring,
			outer + 9.0,
			-PI * 0.5,
			-PI * 0.5 + share * TAU,
			40,
			Color(0.45, 0.95, 0.5, 0.95),
			4.0,
			true,
		)
	draw_circle(ring + get_dot_offset(), dot_radius, band_color)


## Glue flowed at a world point. True when it landed here.
func on_glued(
	at_position: Vector2, radius: float, amount: float
) -> bool:
	if mode == Mode.FINISHED or amount <= 0.0:
		return false
	var reach := maxf(radius, _GLUE_HIT_RADIUS_PX)
	if global_position.distance_to(at_position) > reach:
		return false
	if not has_glue:
		has_glue = true
		_spawn_glue_decal()
	mode = Mode.ACTIVE
	queue_redraw()
	return true


## The dab of glue shows as a glue decal on the layer's art.
func _spawn_glue_decal() -> void:
	if is_instance_valid(glue_decal):
		return
	var layer := get_layer()
	if not is_instance_valid(layer):
		return
	if not is_instance_valid(layer.art):
		return
	if not is_instance_valid(G.level):
		return
	glue_decal = G.level.spawn_decal(
		DecalSpawner.Kind.GLUE_BLOB,
		layer.art,
		global_position,
		34.0,
	)


## 0 good, 1 warning, 2 failed, from the dot and the band.
func get_hold_state() -> int:
	var inner := G.settings.broken_hold_inner_radius_px
	var outer := G.settings.broken_hold_outer_radius_px
	var dot_radius := G.settings.broken_hold_dot_radius_px
	var distance := get_dot_offset().length()
	if distance + dot_radius <= inner:
		return 0
	if distance - dot_radius <= outer:
		return 1
	return 2


## The dot, in this point's own pixels: the held piece's
## offset, amplified, plus its own drift.
func get_dot_offset() -> Vector2:
	var offset := Vector2.ZERO
	if is_instance_valid(piece):
		offset = to_local(piece.global_position)
	return (
		offset * G.settings.broken_hold_dot_scale + _dot_drift
	)


## The drift alone, in this point's pixels. A player (or a
## probe) counters it by moving the piece the other way.
func get_dot_drift() -> Vector2:
	return _dot_drift


## Where the hold ring draws, in world pixels.
func get_ring_global_position() -> Vector2:
	return to_global(_get_ring_center())


func _try_start_hold() -> void:
	if not has_glue or not is_instance_valid(piece):
		return
	if not is_instance_valid(G.level) or not is_instance_valid(
		G.level.hand
	):
		return
	if G.level.hand.get_loose_broken_piece() != piece:
		return
	if global_position.distance_to(piece.global_position) > (
		G.settings.broken_hold_start_radius_px
	):
		return
	is_holding = true
	hold_progress_sec = 0.0
	_dot_drift = Vector2.ZERO
	_dot_drift_velocity = Vector2.ZERO
	_drift_retarget_left_sec = 0.0
	# The game draws over the tools, the piece and the hand.
	z_as_relative = false
	z_index = _HOLD_Z_INDEX
	# Settled work starts from the ideal spot: the hand eases
	# the piece onto this point's exact centre and rotation.
	G.level.hand.begin_broken_piece_hold(piece, global_position)
	piece.align_rotation_to(global_rotation)
	G.audio.play_sound(&"click")


func _step_hold(delta: float) -> void:
	if (
		not is_instance_valid(piece)
		or not is_instance_valid(G.level)
		or G.level.hand.get_loose_broken_piece() != piece
	):
		_end_hold()
		return
	_update_drift(delta)
	match get_hold_state():
		0:
			hold_progress_sec += delta
		2:
			_fail_hold()
			return
	if hold_progress_sec >= maxf(hold_sec, 0.01):
		_complete_hold()


func _update_drift(delta: float) -> void:
	_drift_retarget_left_sec -= delta
	var speed := G.settings.broken_hold_drift_speed_px_per_sec
	if _drift_retarget_left_sec <= 0.0:
		_drift_retarget_left_sec = (
			G.settings.broken_hold_drift_retarget_sec
		)
		_dot_drift_velocity = (
			Vector2.from_angle(randf() * TAU) * speed
		)
	_dot_drift += _dot_drift_velocity * delta
	var limit := G.settings.broken_hold_outer_radius_px * 0.9
	if _dot_drift.length() > limit:
		_dot_drift = _dot_drift.limit_length(limit)
		_dot_drift_velocity = -_dot_drift.normalized() * speed


## Where the ring draws, in this point's own pixels: above
## the point in the world, so a finger on the piece is clear.
func _get_ring_center() -> Vector2:
	var above := global_position + Vector2(
		0.0, -G.settings.broken_hold_ring_offset_px
	)
	return to_local(above)


func _restore_draw_order() -> void:
	z_index = _home_z_index
	z_as_relative = _home_z_as_relative


func _end_hold() -> void:
	is_holding = false
	hold_progress_sec = 0.0
	_dot_drift = Vector2.ZERO
	_dot_drift_velocity = Vector2.ZERO
	_restore_draw_order()


## The dot left the band. The piece drops where it is, and
## the glue stays on the point for the next attempt.
func _fail_hold() -> void:
	var dropped := piece
	_end_hold()
	G.audio.play_sound(&"clunk")
	pulse()
	if is_instance_valid(G.level) and is_instance_valid(dropped):
		G.level.hand.fail_broken_piece_hold(dropped)


func _complete_hold() -> void:
	is_holding = false
	_restore_draw_order()
	hold_progress_sec = maxf(hold_sec, 0.0)
	var attached := piece
	G.audio.play_sound(&"ding")
	if is_instance_valid(attached):
		attached.attach_to_point(self)
	finish()
