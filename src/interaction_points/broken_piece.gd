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
## Where a detached piece lands, in world pixels from where
## the item itself lands.
@export var fall_target_offset := Vector2(150.0, 40.0)
## Set this to the layer that covers the piece. The piece
## then stays hidden, and cannot be grabbed, until that
## layer has been taken off the item.
@export var covering_layer: RepairLayer
## How close a press may land and still grab it, in pixels.
@export var grab_radius_px := 30.0
## The piece's art. It is a Polygon2D in the scene, so its
## shape can be redrawn per piece.
@export var art: Polygon2D

## The item this piece broke off, or null between items.
var item: Repairable
## True once the piece has been glued back onto its point.
var is_installed := false
## True while the level flies it back to the workable area.
var is_returning := false

var _has_detached := false
var _turn_tween: Tween
var _shadow_attached := false


func _ready() -> void:
	G.check(is_instance_valid(art))
	item = _find_item()
	if is_instance_valid(target_point):
		target_point.piece = self
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
				and is_instance_valid(G.level)
				and is_instance_valid(G.level.hand)
				and G.level.hand.get_loose_broken_piece() != self
			),
		0.8,
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


## How far the art reaches from the middle, in world pixels.
func get_radius_px() -> float:
	var radius := 20.0
	if is_instance_valid(art):
		radius = 0.0
		for point in art.polygon:
			radius = maxf(radius, point.length())
	return maxf(radius, 1.0)


## True while this piece has come off the item for good.
func has_detached() -> bool:
	return _has_detached


## True when a press here would grab the piece: the item has
## landed, any covering layer is off, and the piece rests.
func can_grab() -> bool:
	if is_installed or is_returning:
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
	if not is_instance_valid(target_point):
		return
	var target := target_point.global_rotation
	var nearest := rotation + wrapf(
		target - rotation, -PI, PI
	)
	if is_instance_valid(_turn_tween):
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_turn_tween.set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	_turn_tween.tween_property(self, "rotation", nearest, _TURN_SEC)


## The point's hold finished. The piece leaves the hand,
## snaps onto the point and stays there with the item.
func attach_to_point(point: BrokenPoint) -> void:
	is_installed = true
	if is_instance_valid(_turn_tween):
		_turn_tween.kill()
	if is_instance_valid(G.level):
		G.level.hand.clear_loose_broken_piece(self)
	var from_global := global_position
	var layer := point.get_layer()
	if is_instance_valid(layer):
		reparent(layer)
	else:
		reparent(point.get_parent())
	global_position = from_global
	reset_physics_interpolation()
	z_index = 0
	z_as_relative = true
	G.audio.play_sound(&"snap")
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
	if is_instance_valid(_turn_tween):
		_turn_tween.kill()


## The piece has come to rest inside the workable area.
func finish_bench_return() -> void:
	is_returning = false
	z_index = 16
	G.audio.play_sound(&"thud")


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
