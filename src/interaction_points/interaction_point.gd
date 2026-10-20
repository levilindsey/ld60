class_name InteractionPoint
extends Area2D
## Something on an item that a tool acts on: a screw, a clip, a fault.
##
## A point only reacts while its layer is exposed, the outermost layer
## still on the item (docs/design/repairables.md "Points").


enum Type {
	FLAT_HEAD_SCREW,
	PART_SOCKET,
	GRIME_SPOT,
	DUST_CLUMP,
	FAN,
	STUCK_PART,
	BENT_PART,
	SEAT_PART,
	CRACK,
	PHILLIPS_SCREW,
	RUST_SPOT,
	BROKEN_POINT,
	GLUE_SMEAR,
}

enum Mode {
	UNSTARTED,
	ACTIVE,
	FINISHED,
}

enum Role {
	## Holds its layer on, like a screw or a clip.
	FASTENER,
	## A fault that must be fixed.
	REPAIR,
}

const _PULSE_SCALE := 1.6
const _POKE_ANGLE_RAD := 0.25

@export var type := Type.FLAT_HEAD_SCREW
@export var role := Role.REPAIR
## Optional points are extras, such as a coin under the dust. The item
## can finish without them.
@export var is_required := true
## The tools this point reacts to. Any other tool nopes.
@export var accepted_tools: Array[Tool.Type] = []
## What this point turns into when it breaks. Null means it can't break.
@export var broken_scene: PackedScene
## Optional outline of the piece this point acts on: an Area2D
## with polygon or shape children tracing the art, the way a
## part's own Shape is authored. Presses and tool tips land
## anywhere inside it, not just on the point's own small circle,
## and the hint follows it. It carries no collision state of
## its own: the point strips it at ready and tests points
## against it by hand, so it never shows up in physics picking.
@export var shape: Area2D

var mode := Mode.UNSTARTED
## The tool that is IN_USE on this point, or null.
var engaged_tool: Tool

var _pulse_tween: Tween
var _poke_tween: Tween
var _hint_hint: OutlineHint
var _is_hint_active := false
## The scale this point was authored at, captured at ready.
## Points on scaled items are placed big (a screw at 8x), and
## the pulse grows from this, never back to 1.
var _home_scale := Vector2.ONE


func _ready() -> void:
	_home_scale = scale
	_configure_shape_area(shape)
	G.check(monitorable)
	G.check(collision_layer == Settings.PhysicsLayer.INTERACTION_POINTS)


func _physics_process(_delta: float) -> void:
	if is_instance_valid(engaged_tool):
		place_engaged_tool()


## The engaged tool is a puppet: this places it every frame, working
## end on the point. Microgames override it to move the tool their
## own way.
func place_engaged_tool() -> void:
	engaged_tool.place_work_end(global_position)


## The layer this point belongs to, or null.
func get_layer() -> RepairLayer:
	var node := get_parent()
	while is_instance_valid(node):
		if node is RepairLayer:
			return node as RepairLayer
		node = node.get_parent()
	return null


## The item this point belongs to, or null.
func get_item() -> Repairable:
	var layer := get_layer()
	if is_instance_valid(layer):
		return layer.item
	return null


## True while this point's layer is the outermost layer still on.
func is_exposed() -> bool:
	var layer := get_layer()
	return is_instance_valid(layer) and layer.is_exposed()


## True when this point has a usable authored Shape: a polygon
## with at least three points, or a collision shape.
func has_shape() -> bool:
	return (
		is_instance_valid(shape) and _has_usable_shape_area(shape)
	)


## True when a world point lands on this point's authored
## Shape. False when the point has no Shape configured (or its
## Shape went away with the art it was parented under).
func is_point_in_shape(world_point: Vector2) -> bool:
	return (
		is_instance_valid(shape)
		and _is_point_in_shape_area(shape, world_point)
	)


## The authored Shape's first polygon, in world points.
func get_shape_world_polygon() -> PackedVector2Array:
	if not is_instance_valid(shape):
		return PackedVector2Array()
	return _get_shape_area_world_polygon(shape)


## The authored Shape's first polygon, in this point's own
## points, for outlines that draw as children here.
func get_shape_local_polygon() -> PackedVector2Array:
	if not is_instance_valid(shape):
		return PackedVector2Array()
	return _get_shape_area_local_polygon(shape)


func accepts(tool: Tool) -> bool:
	return accepted_tools.has(tool.type)


## True when a tool press here would start something.
func can_engage() -> bool:
	return (
		mode == Mode.UNSTARTED
		and is_exposed()
		and is_visible_in_tree()
	)


## True while this point is required and not FINISHED.
func needs_work() -> bool:
	return is_required and mode != Mode.FINISHED


## True while this FASTENER holds its layer on.
func is_fastened() -> bool:
	return role == Role.FASTENER and mode != Mode.FINISHED


## Called on each FASTENER when its layer goes back on.
func set_install_mode() -> void:
	mode = Mode.UNSTARTED


## Starts this point's microgame with a tool. The tool goes IN_USE and
## this point places it until finish() or release_tool().
func engage(tool: Tool) -> void:
	engaged_tool = tool
	mode = Mode.ACTIVE
	tool.start_use(self)


## Lets go of the engaged tool, which goes back to the hand.
func release_tool() -> void:
	var tool := engaged_tool
	engaged_tool = null
	if is_instance_valid(tool):
		tool.stop_use()


## Marks this point done and tells its layer and its item.
func finish() -> void:
	mode = Mode.FINISHED
	release_tool()
	var layer := get_layer()
	if is_instance_valid(layer):
		layer.on_point_finished(self)
	var item := get_item()
	if is_instance_valid(item):
		item.on_point_finished(self)


## The empty hand pressed this point: the "inspect" action. Points
## override it to squeak, rattle or jerk.
func on_poked() -> void:
	G.audio.play_sound(&"click")
	if is_instance_valid(_poke_tween):
		_poke_tween.kill()
	rotation = 0.0
	_poke_tween = create_tween()
	var step_sec := G.settings.point_pulse_sec / 3.0
	_poke_tween.tween_property(self, "rotation", _POKE_ANGLE_RAD, step_sec)
	_poke_tween.tween_property(self, "rotation", -_POKE_ANGLE_RAD, step_sec)
	_poke_tween.tween_property(self, "rotation", 0.0, step_sec)


## One short pulse that shows this point still needs work.
## It grows from the authored scale and returns to it, so a
## point placed big on a scaled item keeps its size.
func pulse() -> void:
	if is_instance_valid(_pulse_tween):
		_pulse_tween.kill()
	scale = _home_scale
	_pulse_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	var half_sec := G.settings.point_pulse_sec * 0.5
	_pulse_tween.tween_property(
		self,
		"scale",
		_home_scale * _PULSE_SCALE,
		half_sec,
	)
	_pulse_tween.tween_property(self, "scale", _home_scale, half_sec)


## A hint smaller than this across, in world pixels, marks
## nothing: a fault's hit circle on a much scaled item (the
## keyboard at a sixth of its authored size) traces a ring a
## few pixels wide. Small hint polygons grow around their
## middle until they reach this, so every point kind reads
## at the same world size. Bigger shapes keep their trace.
const _MIN_HINT_WORLD_PX := 30.0


## Shows or hides the idle hint outline around this point. The
## hint tracker calls it after its delay, and clears it as soon as
## the player works on the point. The outline follows the point's
## own collision shape, so every point kind highlights in place.
func set_hint_active(is_active: bool) -> void:
	_is_hint_active = is_active
	if is_active:
		var points := _get_hint_polygon()
		if points.size() < 3:
			return
		if not is_instance_valid(_hint_hint):
			_hint_hint = OutlineHint.new()
			add_child(_hint_hint)
		_hint_hint.polygon = _grown_to_readable(points)
		_hint_hint.set_active(true)
	elif is_instance_valid(_hint_hint):
		_hint_hint.set_active(false)


## `points` scaled up around their middle until their world
## size reaches `_MIN_HINT_WORLD_PX` across. Returned as-is
## when they already read, or cannot be measured.
func _grown_to_readable(
	points: PackedVector2Array,
) -> PackedVector2Array:
	var transform := global_transform
	var rect := Rect2(transform * points[0], Vector2.ZERO)
	var middle := Vector2.ZERO
	for point in points:
		rect = rect.expand(transform * point)
		middle += point
	middle /= points.size()
	var biggest := maxf(rect.size.x, rect.size.y)
	if biggest <= 0.001 or biggest >= _MIN_HINT_WORLD_PX:
		return points
	var factor := _MIN_HINT_WORLD_PX / biggest
	var grown := PackedVector2Array()
	for point in points:
		grown.append(middle + (point - middle) * factor)
	return grown


## True while the idle hint outline shows on this point.
func is_hint_active() -> bool:
	return (
		_is_hint_active
		and is_instance_valid(_hint_hint)
		and _hint_hint.is_active()
	)


func _get_hint_polygon() -> PackedVector2Array:
	var shaped := get_shape_local_polygon()
	if shaped.size() >= 3:
		return shaped
	for child in get_children():
		if child is CollisionShape2D:
			var points := OutlineHint.get_shape_polygon(
				child as CollisionShape2D,
			)
			if points.size() >= 3:
				return points
	var points := PackedVector2Array()
	for index in 12:
		var angle := TAU * float(index) / 12.0
		points.append(Vector2.from_angle(angle) * 22.0)
	return points


## An authored Shape arrives with no collision state configured
## (it was added in the editor as a bare outline). Strip anything
## that could make physics see it: no layer, no mask, no
## monitoring either way. Points are tested against it by hand.
## Shared with subclasses that carry more than one authored
## shape (a socket's good and bad part shapes).
func _configure_shape_area(shape_area: Area2D) -> void:
	if not is_instance_valid(shape_area):
		return
	shape_area.collision_layer = 0
	shape_area.collision_mask = 0
	shape_area.monitoring = false
	shape_area.monitorable = false


## True when an authored Shape has an outline to test: a polygon
## with at least three points, or a collision shape.
func _has_usable_shape_area(shape_area: Area2D) -> bool:
	if not is_instance_valid(shape_area):
		return false
	for child in shape_area.get_children():
		if child is CollisionPolygon2D:
			if (child as CollisionPolygon2D).polygon.size() >= 3:
				return true
		elif child is CollisionShape2D:
			if is_instance_valid((child as CollisionShape2D).shape):
				return true
	return false


## True when a world point lands on an authored Shape: any of
## its polygons, or inside any of its collision shapes. False
## when no such shape was given.
func _is_point_in_shape_area(
	shape_area: Area2D, world_point: Vector2
) -> bool:
	if not is_instance_valid(shape_area):
		return false
	for child in shape_area.get_children():
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


## An authored Shape's first polygon, in world points.
func _get_shape_area_world_polygon(
	shape_area: Area2D
) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_instance_valid(shape_area):
		return points
	for child in shape_area.get_children():
		if child is CollisionPolygon2D:
			var polygon_node := child as CollisionPolygon2D
			for point in polygon_node.polygon:
				points.append(
					polygon_node.global_transform * point
				)
			return points
	return points


## An authored Shape's first polygon, in this point's own
## points, for outlines that draw as children here.
func _get_shape_area_local_polygon(
	shape_area: Area2D
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var to_local := global_transform.affine_inverse()
	for world_point in _get_shape_area_world_polygon(shape_area):
		points.append(to_local * world_point)
	return points


## Swaps this point for an instance of `broken_scene` with the same
## transform. Returns the new point, or null when it can't break.
func break_point() -> InteractionPoint:
	if broken_scene == null:
		return null
	var broken: InteractionPoint = broken_scene.instantiate()
	var parent := get_parent()
	parent.add_child(broken)
	parent.move_child(broken, get_index())
	broken.transform = transform
	release_tool()
	queue_free()
	return broken
