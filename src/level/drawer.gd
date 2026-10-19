class_name Drawer
extends Node2D
## One diegetic parts drawer. It rests in a vertical stack on the
## left side of the level showing its front face. A press plays the
## "open" animation, which flips it to a top-down view, and then the
## `%Mover` wrapper slides it to the center of the level. The
## animation drives the sprites under `%Visual`, so the slide tweens
## the wrapper instead. A press outside an open drawer slides it
## back and reverses the animation.
##
## While the drawer is in its slot the sprites show through
## `%ClippingSpace`, whose L-shaped mask hides the part of the art
## that is still inside the desk (like the screws sliding out of
## their holes). Once the open animation finishes, the drawer swaps
## to the duplicate `%VisualUnclipped` group for the trip to the
## center, and swaps back before the animation reverses. One
## `AnimationPlayer` drives both groups, so they never drift apart.
##
## Parts live in the level, not in the drawer. The level fades this
## drawer's stored parts in once it is fully open and back out as
## soon as it starts to close (the `opened` and `close_started`
## signals).


signal opened
signal close_started
signal closed

enum State {
	CLOSED,
	OPENING,
	OPEN,
	CLOSING,
	STORING,
}

const _OPEN_ANIMATION := &"open"
## Where an opened drawer sits on the level, in world space.
const _CENTER_GLOBAL_POSITION := Vector2(0.0, 0.0)
## How far inside `%ContentsArea` a stored part may rest, so no
## part hangs over the drawer's rim.
const _INTERIOR_MARGIN_PX := 40.0
## The point in the open animation where the slide out of the slot
## ends and the turn to the top-down view begins. A drawer taking a
## part back pauses here, pulled out but still facing forward.
const _SLIDE_FRACTION := 0.375
## How far above its top edge a returning part rises, in world
## pixels, before it sinks back down inside.
const _PUT_AWAY_CLEARANCE_PX := 50.0
## How much bigger the drawer gets on its trip to the center,
## as it turns from the front view to the top-down view. It
## shrinks back on the way home. Stored parts are level
## children, not drawer children, so they keep their own
## scale while the drawer grows around them.
const _CENTER_SCALE_MULTIPLIER := 2.0

var state := State.CLOSED
## This drawer's slot in the level's stack, counting from 0.
var drawer_index := -1

var _open_fraction := 0.0
var _is_clipped := true
var _hint_hint: OutlineHint
var _is_hint_active := false
var _tween: Tween
var _fraction_tween: Tween
## Bumped by `reset_closed()`, so an open or close that was cut
## short never resumes and moves the drawer later.
var _generation := 0
var _scaler_home_scale := Vector2.ONE


func _ready() -> void:
	_scaler_home_scale = _get_scaler().scale
	_set_clipped(true)
	_apply_open_fraction(0.0)


## The wrapper that carries the drawer art. Scaling it grows
## the drawer on its trip to the center.
func _get_scaler() -> Node2D:
	return get_node("Mover/Scaler") as Node2D


## Shows the clipped sprite group in the slot, or the unclipped
## duplicate once the drawer is out and on its way to the center.
func _set_clipped(is_clipped: bool) -> void:
	_is_clipped = is_clipped
	(%ClippingSpace as CanvasItem).visible = is_clipped
	(%VisualUnclipped as CanvasItem).visible = not is_clipped


## True while the drawer is between poses. Presses wait it out, and
## no part may be put away into a drawer that is still shutting.
func is_busy() -> bool:
	return state != State.CLOSED and state != State.OPEN


## True when a dragged part may be put away into this drawer: it is
## shut and idle, or already open in the center.
func can_take_part() -> bool:
	return state == State.CLOSED or state == State.OPEN


## True when a world position lands on the drawer as it is drawn
## now, shut in its slot or open in the center.
func has_global_point(global_point: Vector2) -> bool:
	return get_hit_global_rect().has_point(global_point)


## The drawer's face in world space, following the wrapper. The
## size comes from the hit shape itself, so the check follows the
## scene when the shape is resized there.
func get_hit_global_rect() -> Rect2:
	var transform := (%HitArea as Area2D).global_transform
	var shape := (
		(%HitArea as Area2D).get_node("CollisionShape2D")
		as CollisionShape2D
	).shape as RectangleShape2D
	var half_size := shape.size * 0.5
	var corners := PackedVector2Array([
		transform * Vector2(-half_size.x, -half_size.y),
		transform * Vector2(half_size.x, -half_size.y),
		transform * Vector2(half_size.x, half_size.y),
		transform * Vector2(-half_size.x, half_size.y),
	])
	var rect := Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		rect = rect.expand(corner)
	return rect


## Shows or hides the idle hint outline around this drawer's
## face, where it rests shut in its slot. The tracker lights every
## drawer at once for a fetch step, because the needed part could
## be in any of them. The outline is placed while the drawer is
## shut, so it does not follow the trip to the center.
func set_hint_active(is_active: bool) -> void:
	_is_hint_active = is_active
	if is_active:
		if not is_instance_valid(_hint_hint):
			var rect := get_hit_global_rect()
			var points := PackedVector2Array()
			points.append(to_local(rect.position))
			points.append(
				to_local(rect.position + Vector2(rect.size.x, 0.0)),
			)
			points.append(to_local(rect.position + rect.size))
			points.append(
				to_local(rect.position + Vector2(0.0, rect.size.y)),
			)
			if points.size() < 3:
				return
			_hint_hint = OutlineHint.new()
			add_child(_hint_hint)
			_hint_hint.polygon = points
		_hint_hint.set_active(true)
	elif is_instance_valid(_hint_hint):
		_hint_hint.set_active(false)


## True while the idle hint outline shows on this drawer.
func is_hint_active() -> bool:
	return (
		_is_hint_active
		and is_instance_valid(_hint_hint)
		and _hint_hint.is_active()
	)


## The drawer's inside in `%ContentsArea`'s shape-local
## coordinates, clear of its rim. `%ContentsArea` marks the
## inside in the scene, the way the hit shape marks the face.
## A part's drawer spot (`Part.drawer_spot_local`) lives in
## these coordinates, so it means the same spot whatever pose
## the drawer is passing through.
func get_interior_local_rect() -> Rect2:
	var shape := (
		(%ContentsArea as Area2D).get_node("CollisionShape2D")
		as CollisionShape2D
	).shape as RectangleShape2D
	return Rect2(-shape.size * 0.5, shape.size).grow(
		-_INTERIOR_MARGIN_PX
	)


## A spot in interior-local coordinates (see
## `get_interior_local_rect()`) as a world position in the
## drawer's current pose.
func get_interior_global_position(local_point: Vector2) -> Vector2:
	var shape_node := (
		(%ContentsArea as Area2D).get_node("CollisionShape2D")
		as CollisionShape2D
	)
	return shape_node.global_transform * local_point


## How many world pixels one interior-local unit spans on each
## axis once the drawer sits open in the center, whatever pose
## it is in now: the trip to the center multiplies the scaler,
## so the closed drawer's measure is scaled back up by the
## share the scaler still has to grow. The level lays drawer
## spots out with this, so spacing is judged in the pixels the
## player will actually see.
func get_open_interior_world_per_local() -> Vector2:
	var shape_node := (
		(%ContentsArea as Area2D).get_node("CollisionShape2D")
		as CollisionShape2D
	)
	var basis := shape_node.global_transform
	var scaler_scale := _get_scaler().scale
	var grow := Vector2(
		_scaler_home_scale.x
		* _CENTER_SCALE_MULTIPLIER
		/ maxf(scaler_scale.x, 0.0001),
		_scaler_home_scale.y
		* _CENTER_SCALE_MULTIPLIER
		/ maxf(scaler_scale.y, 0.0001),
	)
	return Vector2(basis.x.length(), basis.y.length()) * grow


## Where a stored part rests in the world in the drawer's
## current pose: at its drawer spot when the level gave it one
## for this item, anywhere inside otherwise.
func get_stored_global_position(part: Part) -> Vector2:
	if part.has_drawer_spot():
		return get_interior_global_position(part.drawer_spot_local)
	return get_random_interior_global_position()


## A random world position inside the open drawer, clear of its
## rim. `%ContentsArea` marks the inside in the scene, the way the
## hit shape marks the face.
func get_random_interior_global_position() -> Vector2:
	var interior := get_interior_local_rect()
	var local_point := Vector2(
		randf_range(interior.position.x, interior.end.x),
		randf_range(interior.position.y, interior.end.y),
	)
	return get_interior_global_position(local_point)


## Slides out of the slot, then turns to the top-down view while
## the wrapper slides to the center. Stored parts appear once
## `opened` fires at the end.
func open_drawer() -> void:
	if state != State.CLOSED:
		return
	state = State.OPENING
	G.audio.play_sound(&"drawer_open")
	var generation := _generation
	_kill_tween()
	await _tween_open_fraction(
		_SLIDE_FRACTION, G.settings.drawer_slide_sec
	).finished
	if generation != _generation:
		return
	# Out of the slot: the unclipped group makes the trip.
	_set_clipped(false)
	_kill_tween()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_parallel()
	_tween.tween_method(
		_apply_open_fraction,
		_open_fraction,
		1.0,
		G.settings.drawer_move_sec,
	)
	_tween.tween_property(
		%Mover,
		"position",
		_mover_center_position(),
		G.settings.drawer_move_sec,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(
		_get_scaler(),
		"scale",
		_scaler_home_scale * _CENTER_SCALE_MULTIPLIER,
		G.settings.drawer_move_sec,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	if generation != _generation:
		return
	state = State.OPEN
	opened.emit()


## Hides the stored parts, turns back and slides to the slot
## together, swaps to the clipped group, then slides home. Called
## while the drawer is still opening, it reverses the opening
## from wherever it has got to.
func close_drawer() -> void:
	if state != State.OPEN and state != State.OPENING:
		return
	state = State.CLOSING
	G.audio.play_sound(&"drawer_close")
	var generation := _generation
	close_started.emit()
	_kill_tween()
	if _is_clipped:
		# Still in the slot: the opening never got the drawer
		# out. Just slide it home.
		await _tween_open_fraction(
			0.0, G.settings.drawer_slide_sec
		).finished
		if generation != _generation:
			return
		state = State.CLOSED
		closed.emit()
		return
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_parallel()
	_tween.tween_method(
		_apply_open_fraction,
		_open_fraction,
		_SLIDE_FRACTION,
		G.settings.drawer_move_sec,
	)
	_tween.tween_property(
		%Mover,
		"position",
		Vector2.ZERO,
		G.settings.drawer_move_sec,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(
		_get_scaler(),
		"scale",
		_scaler_home_scale,
		G.settings.drawer_move_sec,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	if generation != _generation:
		return
	# Back in the slot: the clipped group slides it home.
	_set_clipped(true)
	await _tween_open_fraction(
		0.0, G.settings.drawer_slide_sec
	).finished
	if generation != _generation:
		return
	state = State.CLOSED
	closed.emit()


## Snaps the drawer shut with no animation. The level calls this
## before it restocks the drawers for the next item.
func reset_closed() -> void:
	_generation += 1
	_kill_tween()
	(%AnimationPlayer as AnimationPlayer).stop()
	state = State.CLOSED
	_set_clipped(true)
	(%Mover as Node2D).position = Vector2.ZERO
	_get_scaler().scale = _scaler_home_scale
	_apply_open_fraction(0.0)


## Takes a dragged part back in. A shut drawer opens halfway while
## the part rises over its top edge, the part sinks down inside,
## and then the drawer shuts again. An already open drawer just
## takes the part into itself.
func take_part(part: Part) -> void:
	if not can_take_part() or part.is_returning:
		return
	part.is_returning = true
	# Behind the drawer, so its face covers the part as it
	# sinks back inside.
	part.z_index = 10
	if state == State.OPEN:
		await _sink_part(part)
		_store_part(part)
		part.global_position = get_stored_global_position(part)
		part.is_returning = false
		return
	state = State.STORING
	_tween_open_fraction(_SLIDE_FRACTION)
	await _sink_part(part)
	_store_part(part)
	await _tween_open_fraction(0.0, G.settings.drawer_slide_sec)
	state = State.CLOSED
	closed.emit()


## Puts every loose part left out on the bench away into this
## drawer, the way `take_part()` does, but the drawer opens halfway
## only once for the whole batch.
func store_parts(parts: Array[Part]) -> void:
	if state != State.CLOSED:
		for part in parts:
			_store_part(part)
		return
	var loose: Array[Part] = []
	for part in parts:
		if is_instance_valid(part) and not part.is_returning:
			part.is_returning = true
			part.z_index = 10
			loose.append(part)
	if loose.is_empty():
		return
	state = State.STORING
	_tween_open_fraction(_SLIDE_FRACTION)
	var top_y := get_hit_global_rect().position.y
	var up_tween := create_tween()
	up_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	up_tween.set_parallel()
	for index in loose.size():
		up_tween.tween_property(
			loose[index],
			"global_position",
			Vector2(
				loose[index].global_position.x,
				top_y - _PUT_AWAY_CLEARANCE_PX,
			),
			G.settings.part_put_away_sec,
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(
			index * 0.06
		)
	await up_tween.finished
	var down_tween := create_tween()
	down_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	down_tween.set_parallel()
	for index in loose.size():
		down_tween.tween_property(
			loose[index],
			"global_position",
			get_stored_global_position(loose[index]),
			G.settings.part_put_away_sec,
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(
			index * 0.06
		)
	await down_tween.finished
	for part in loose:
		_store_part(part)
	await _tween_open_fraction(0.0, G.settings.drawer_slide_sec)
	state = State.CLOSED
	closed.emit()


## Moves one part up over the drawer's top edge and then down
## inside. The drawer's own half-open tween runs alongside; it is
## never awaited here, because awaiting a tween that already
## finished never resumes.
func _sink_part(part: Part) -> void:
	var top_y := get_hit_global_rect().position.y
	var up_tween := part.create_tween()
	up_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	up_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up_tween.tween_property(
		part,
		"global_position",
		Vector2(
			part.global_position.x,
			top_y - _PUT_AWAY_CLEARANCE_PX,
		),
		G.settings.part_put_away_sec,
	)
	await up_tween.finished
	var down_tween := part.create_tween()
	down_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	down_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	down_tween.tween_property(
		part,
		"global_position",
		get_stored_global_position(part),
		G.settings.part_put_away_sec,
	)
	await down_tween.finished


## Files a part away inside this drawer and hides it until the
## drawer opens again. The part goes back to the turn of its
## drawer spot, so it rests the same way every time this drawer
## opens for the item.
func _store_part(part: Part) -> void:
	G.audio.play_sound(&"click")
	part.is_stored = true
	part.is_returning = false
	part.drawer_index = drawer_index
	part.z_index = 10
	if part.has_drawer_spot():
		part.rotation = part.drawer_spot_rotation
	part.hide()


## The wrapper's local position when the drawer sits in the center
## of the level. The wrapper inherits this drawer's scale, so the
## world offset is divided back down.
func _mover_center_position() -> Vector2:
	var mover := %Mover as Node2D
	var world_offset := _CENTER_GLOBAL_POSITION - mover.global_position
	var scale := global_transform.get_scale()
	return mover.position + Vector2(
		world_offset.x / scale.x,
		world_offset.y / scale.y,
	)


## Tweens the open animation to a fraction of its length over
## `duration_sec` and holds it there. Returns the tween.
func _tween_open_fraction(
	to_fraction: float,
	duration_sec: float = G.settings.drawer_half_open_sec,
) -> Tween:
	if is_instance_valid(_fraction_tween):
		_fraction_tween.kill()
	_fraction_tween = create_tween()
	_fraction_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_fraction_tween.tween_method(
		_apply_open_fraction,
		_open_fraction,
		to_fraction,
		duration_sec,
	)
	return _fraction_tween


func _apply_open_fraction(fraction: float) -> void:
	# A fraction left over from a finished sequence must never
	# freeze a drawer that has settled open in the center.
	if state == State.OPEN:
		return
	_open_fraction = fraction
	var player := %AnimationPlayer as AnimationPlayer
	if player.current_animation != _OPEN_ANIMATION:
		player.play(_OPEN_ANIMATION)
	player.seek(
		fraction * player.get_animation(_OPEN_ANIMATION).length,
		true,
	)
	# Freeze the pose here until a full play restores the speed.
	player.speed_scale = 0.0


func _kill_tween() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	if is_instance_valid(_fraction_tween):
		_fraction_tween.kill()
