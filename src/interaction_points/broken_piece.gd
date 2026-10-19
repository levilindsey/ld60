class_name BrokenPiece
extends Node2D
## The piece that broke off a BrokenPoint (docs/design/
## glue.md). It is placed by hand inside a repairable, apart
## from its point, and rides in with the item. From there it
## is either grabbed off the item, or it falls to the bench
## on its own when the item arrives. On the bench it moves
## like any other loose piece. Grabbing it turns it to the
## rotation its point expects.

## Seconds the piece takes to turn to its point's rotation
## when it is grabbed, and to settle onto the point.
const _TURN_SEC := 0.25
const _FIT_SEC := 0.15

## The point this piece reattaches to.
@export var target_point: BrokenPoint
## True: the piece falls off on its own as the item arrives
## and lands at fall_target_offset. False: it rides in on
## the item until the player grabs it.
@export var starts_detached := false
## True: the piece starts glued on, with its point finished.
## It only breaks when `knock_off()` is called.
@export var starts_installed := false
## Where a detached piece lands, in world pixels from where
## the item itself lands.
@export var fall_target_offset := Vector2(150.0, 40.0)
## Set this to the layer that covers the piece. The piece
## then stays hidden, and cannot be grabbed, until that
## layer has been taken off the item.
@export var covering_layer: RepairLayer
## True: while on the item, the piece draws behind its layer's art,
## like a far wheel. Put it before the art in the scene too.
@export var is_behind_layer_art := false
## How close a press may land and still grab it, in pixels.
@export var grab_radius_px := 30.0
## The piece's art: a Polygon2D, so its shape can be redrawn
## per piece, or a Sprite2D.
@export var art: CanvasItem
## The piece's own outline, an Area2D with polygon or shape
## children tracing the art. A press grabs the piece anywhere
## inside it, not just within `grab_radius_px` of its middle,
## and the outline sets how far the art reaches. It carries no
## collision state of its own: the piece switches its layers
## and monitoring off at ready and tests points against it by
## hand, so it never shows up in the hand's physics picking.
@export var shape: Area2D

## The item this piece broke off, or null between items.
var item: Repairable
## True once the piece has been glued back onto its point.
var is_installed := false
## True while the level flies it back to the workable area.
var is_returning := false
## True while a failed hold's flick is still in the air.
var is_flicking := false
## True while its point's hold game is running. The point
## moves the piece then, not the hand.
var is_in_hold := false

var _has_detached := false
var _turn_tween: Tween
var _flick_tween: Tween
var _shadow_attached := false


func _ready() -> void:
	_configure_shape()
	G.check(is_instance_valid(art))
	item = _find_item()
	if is_instance_valid(target_point):
		target_point.piece = self
		if starts_installed:
			is_installed = true
			target_point.mode = InteractionPoint.Mode.FINISHED
	# A piece that falls on arrival is reparented in the same
	# call stack, before a shadow's deferred sibling insert
	# could run. It gets its shadow once it has left instead.
	if not starts_detached:
		_attach_shadow()


## The bench shadow, built from the art like a loose part's.
func _attach_shadow() -> void:
	if _shadow_attached:
		return
	_shadow_attached = true
	DropShadow.attach_silhouette(
		self,
		[art],
		Vector2(0.0, 6.0),
		func() -> bool:
			return (
				_has_detached
				and not is_installed
				and not is_returning
				and not is_flicking
				and is_instance_valid(G.level)
				and is_instance_valid(G.level.hand)
				and G.level.hand.get_loose_broken_piece() != self
			),
		0.8,
		true,
	)


func _process(_delta: float) -> void:
	if _has_detached or is_installed:
		return
	if is_instance_valid(covering_layer):
		visible = not covering_layer.is_on


## Names its point after either side was placed. A probe (or
## a spawner) that adds the piece after its point calls this.
func setup_target(point: BrokenPoint) -> void:
	target_point = point
	if is_instance_valid(point):
		point.piece = self


## The Shape areas arrive with no collision state configured
## (they were added in the editor as bare outlines). Strip
## anything that could make physics see them: no layer, no
## mask, no monitoring either way. Points are tested against
## them by hand in `is_point_in_shape()`.
func _configure_shape() -> void:
	if not is_instance_valid(shape):
		return
	shape.collision_layer = 0
	shape.collision_mask = 0
	shape.monitoring = false
	shape.monitorable = false


## True when the piece has a usable authored Shape: a polygon
## with at least three points, or a collision shape.
func has_shape() -> bool:
	if not is_instance_valid(shape):
		return false
	for child in shape.get_children():
		if child is CollisionPolygon2D:
			if (child as CollisionPolygon2D).polygon.size() >= 3:
				return true
		elif child is CollisionShape2D:
			if is_instance_valid((child as CollisionShape2D).shape):
				return true
	return false


## True when a world point lands on the piece's Shape: any
## of its polygons, or inside any of its collision shapes.
## False when the piece has no Shape configured.
func is_point_in_shape(world_point: Vector2) -> bool:
	if not is_instance_valid(shape):
		return false
	for child in shape.get_children():
		if child is CollisionPolygon2D:
			var polygon_node := child as CollisionPolygon2D
			if polygon_node.polygon.size() < 3:
				continue
			var local := (
				polygon_node.global_transform.affine_inverse()
				* world_point
			)
			if Geometry2D.is_point_in_polygon(
				local, polygon_node.polygon
			):
				return true
		elif child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if not is_instance_valid(shape_node.shape):
				continue
			var local := (
				shape_node.global_transform.affine_inverse()
				* world_point
			)
			if _is_point_in_collision_shape(local, shape_node.shape):
				return true
	return false


## The Shape's first polygon, in world points, for outlines
## and hints that want the piece's real outline.
func get_shape_world_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_instance_valid(shape):
		return points
	for child in shape.get_children():
		if child is CollisionPolygon2D:
			var polygon_node := child as CollisionPolygon2D
			for point in polygon_node.polygon:
				points.append(
					polygon_node.global_transform * point
				)
			return points
	return points


func _is_point_in_collision_shape(
	local_point: Vector2, collision_shape: Shape2D
) -> bool:
	if collision_shape is RectangleShape2D:
		var rectangle := collision_shape as RectangleShape2D
		return Rect2(
			-rectangle.size * 0.5, rectangle.size
		).has_point(local_point)
	if collision_shape is CircleShape2D:
		var circle := collision_shape as CircleShape2D
		return local_point.length() <= circle.radius
	if collision_shape is CapsuleShape2D:
		var capsule := collision_shape as CapsuleShape2D
		var half := capsule.height * 0.5 - capsule.radius
		var nearest := Vector2(
			0.0, clampf(local_point.y, -half, half)
		)
		return local_point.distance_to(nearest) <= capsule.radius
	return false


## How far the art reaches from the middle, in world pixels.
## The authored Shape wins when it has one; the drawn art is
## the fallback.
func get_radius_px() -> float:
	var shape_points := get_shape_world_polygon()
	if shape_points.size() >= 3:
		var shape_radius := 0.0
		for point in shape_points:
			shape_radius = maxf(
				shape_radius,
				point.distance_to(global_position),
			)
		return maxf(shape_radius, 1.0)
	var radius := 20.0
	if art is Polygon2D:
		radius = 0.0
		for point in (art as Polygon2D).polygon:
			radius = maxf(radius, point.length())
	elif art is Sprite2D:
		var sprite := art as Sprite2D
		var rect := sprite.get_rect()
		radius = 0.0
		for corner in [
			rect.position,
			rect.end,
			Vector2(rect.position.x, rect.end.y),
			Vector2(rect.end.x, rect.position.y),
		]:
			radius = maxf(radius, (corner * sprite.scale).length())
	return maxf(radius, 1.0)


## True while this piece has come off the item for good.
func has_detached() -> bool:
	return _has_detached


## True when a press here would grab the piece: the item has
## landed, any covering layer is off, and the piece rests.
func can_grab() -> bool:
	if is_installed or is_returning or is_flicking:
		return false
	if not is_visible_in_tree():
		return false
	if _has_detached:
		return true
	if is_instance_valid(covering_layer) and covering_layer.is_on:
		return false
	if is_instance_valid(item) and item.mode != (
		Repairable.Mode.UNDER_REPAIR
	):
		return false
	var layer := _find_layer()
	if is_instance_valid(layer):
		return layer.is_exposed()
	return true


## The hand took this piece. It leaves the item if it was
## still on it, then turns to the rotation its point wants.
func on_grabbed() -> void:
	if is_instance_valid(G.level):
		G.level.cancel_bench_return(self)
		if not _has_detached:
			_detach_to_bench()
	if is_instance_valid(target_point):
		align_rotation_to(target_point.global_rotation)


## Turns to a world rotation the short way, in the fingers.
func align_rotation_to(target_global_rotation: float) -> void:
	var nearest := rotation + wrapf(
		target_global_rotation - rotation, -PI, PI
	)
	if is_instance_valid(_turn_tween):
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_turn_tween.set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	_turn_tween.tween_property(self, "rotation", nearest, _TURN_SEC)


## A failed hold tosses the piece: a little hop up and to a
## random side, turning as it goes, then it rests there.
func flick_away() -> void:
	if is_installed:
		return
	if is_instance_valid(_flick_tween):
		_flick_tween.kill()
	if is_instance_valid(_turn_tween):
		_turn_tween.kill()
	is_flicking = true
	var side := 1.0 if randf() < 0.5 else -1.0
	var from_position := global_position
	var target := from_position + Vector2(
		side * randf_range(48.0, 84.0), randf_range(6.0, 22.0)
	)
	if is_instance_valid(G.level):
		target = G.level.get_workable_area_target(
			target,
			get_radius_px() + G.settings.workable_edge_padding_px,
		)
	var from_rotation := rotation
	var target_rotation := (
		from_rotation + side * randf_range(0.4, 0.9)
	)
	_flick_tween = create_tween()
	_flick_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_flick_tween.tween_method(
		_set_flick_progress.bind(
			from_position, target, from_rotation, target_rotation
		),
		0.0,
		1.0,
		0.38,
	)
	_flick_tween.tween_callback(_on_flick_landed)


func _set_flick_progress(
	progress: float,
	from_position: Vector2,
	target: Vector2,
	from_rotation: float,
	target_rotation: float,
) -> void:
	var rise := sin(progress * PI) * 42.0
	global_position = from_position.lerp(target, progress) + (
		Vector2(0.0, -rise)
	)
	rotation = lerpf(from_rotation, target_rotation, progress)


func _on_flick_landed() -> void:
	is_flicking = false
	reset_physics_interpolation()
	G.audio.play_sound(&"part_drop_large")


## The point's hold finished. The piece leaves the hand,
## snaps onto the point and stays there with the item.
func attach_to_point(point: BrokenPoint) -> void:
	is_installed = true
	if is_instance_valid(_flick_tween):
		_flick_tween.kill()
	is_flicking = false
	if is_instance_valid(_turn_tween):
		_turn_tween.kill()
	if is_instance_valid(G.level):
		G.level.hand.clear_loose_broken_piece(self)
	var from_global := global_position
	var layer := point.get_layer()
	if is_instance_valid(layer):
		reparent(layer)
		if is_behind_layer_art and is_instance_valid(layer.art):
			layer.move_child(self, layer.art.get_index())
	else:
		reparent(point.get_parent())
	global_position = from_global
	reset_physics_interpolation()
	z_index = 0
	z_as_relative = true
	G.audio.play_sound(&"rattle_snap")
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		self, "global_position", point.global_position, _FIT_SEC
	)
	tween.parallel().tween_property(
		self,
		"rotation",
		point.global_rotation,
		_FIT_SEC,
	)


## Breaks an installed piece off mid-repair: its point needs
## glue and the piece again, and the piece falls to the bench
## toward a world position.
func knock_off(target_global_position: Vector2) -> void:
	if not is_installed:
		return
	is_installed = false
	if is_instance_valid(target_point):
		target_point.reset_for_reglue()
	detach_for_fall(target_global_position)


## Falls off as the item arrives, toward a world position.
## The level gives it the loose pieces' flight, bounce and
## skid, so it lands like a part and keeps a random turn.
func detach_for_fall(target_global_position: Vector2) -> void:
	if _has_detached:
		return
	_detach_to_bench()
	rotation = randf_range(-PI, PI)
	if is_instance_valid(G.level):
		G.level.start_broken_piece_fall(
			self, target_global_position
		)


## The level starts flying this piece back in.
func start_bench_return() -> void:
	is_returning = true
	if is_instance_valid(_flick_tween):
		_flick_tween.kill()
	is_flicking = false
	if is_instance_valid(_turn_tween):
		_turn_tween.kill()


## The sound of the piece hitting the bench, played by the
## level at its first bounce, not when it comes to rest.
func play_landing_sound() -> void:
	G.audio.play_sound(&"part_drop_large")


## The piece has come to rest inside the workable area.
func finish_bench_return() -> void:
	is_returning = false
	z_index = 16


func _detach_to_bench() -> void:
	_has_detached = true
	visible = true
	var kept_global := global_position
	if is_instance_valid(G.level):
		reparent(G.level)
		G.level.register_broken_piece(self)
	global_position = kept_global
	z_index = 16
	z_as_relative = false
	reset_physics_interpolation()
	# After the reparent, so the shadow's deferred sibling
	# insert lands under the new parent too.
	_attach_shadow()


func _find_item() -> Repairable:
	var node := get_parent()
	while is_instance_valid(node):
		if node is Repairable:
			return node as Repairable
		node = node.get_parent()
	return null


func _find_layer() -> RepairLayer:
	var node := get_parent()
	while is_instance_valid(node):
		if node is RepairLayer:
			return node as RepairLayer
		node = node.get_parent()
	return null
