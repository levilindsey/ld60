class_name Part
extends Node2D
## A replacement part from the parts drawers. It rests loose on the
## bench or hidden inside a drawer until the player drags it out.
## Dragging it onto an empty socket fits it; dragging it back over a
## drawer puts it away (docs/design/parts_bin.md). While loose it
## renders over the top of repairables (the z_index in part.tscn);
## once installed it layers with its item. Picking it up and setting
## it down each turn it a bit in the fingers. Fitting it into its
## socket instead turns it to the socket's own orientation.


enum Type {
	GEAR,
	TUBE,
	TV_CONTROLS,
	LETTER_KEY,
	SPACEBAR,
	LED,
	JOYSTICK,
	CIRCUIT,
	CRYSTAL,
	BOLT,
	NUT,
}

## Seconds the part takes to snap into a socket.
const _FIT_SEC := 0.15
## How many times the part jerks in the "nope" shake.
const _NOPE_SHAKE_STEPS := 4
## Seconds a pick-up or set-down turn takes.
const _TURN_SEC := 0.25
## How far a pick-up or set-down turn goes, in radians. The least
## still reads as a turn, so every grab and drop moves it a bit.
const _TURN_MIN_RAD := 0.2
const _TURN_MAX_RAD := 0.5
## Real part art per kind, where it exists: the overlay image,
## the piece's region on it, and how long its longer side
## runs on the bench in world pixels. That bench length is
## the fitted piece's own world length (its region times its
## item's scale), so a part is the same size in the drawer,
## in the hand and in its socket. Kinds with no art yet keep
## the placeholder polygon. A new kind gets art by adding a
## row here; nothing else needs to change.
const _ART := {
	Type.GEAR: [
		"res://assets/images/repairables/gear.png",
		Rect2(567, 316.5, 615, 609.5),
		76.0,
	],
	Type.TUBE: [
		"res://assets/images/repairables/radio_good_bulb.png",
		Rect2(1059, 587.5, 227.5, 497),
		119.0,
	],
	Type.TV_CONTROLS: [
		"res://assets/images/repairables/tv_controls.png",
		Rect2(1108.5, 459.5, 283.5, 507.5),
		132.0,
	],
	Type.LETTER_KEY: [
		"res://assets/images/repairables/keyss_letter_key.png",
		Rect2(560, 750.5, 60, 47),
		16.0,
	],
	Type.SPACEBAR: [
		"res://assets/images/repairables/keyss_spacebar.png",
		Rect2(648, 781, 454, 50),
		118.0,
	],
	Type.LED: [
		"res://assets/images/repairables/piano_good_led.png",
		Rect2(113.5, 359, 209, 55),
		46.0,
	],
	Type.JOYSTICK: [
		"res://assets/images/repairables/atari_joystick_good.png",
		Rect2(617.5, 233.5, 418, 497.5),
		159.0,
	],
	Type.CIRCUIT: [
		"res://assets/images/repairables/gamenwatch_chip_good.png",
		Rect2(419.5, 404.5, 268.5, 382.5),
		99.0,
	],
	Type.CRYSTAL: [
		"res://assets/images/repairables/shrinkray_fixed_crystal.png",
		Rect2(329, 166, 53, 58),
		35.0,
	],
	Type.BOLT: [
		"res://assets/images/repairables/bolt.png",
		Rect2(646, 295.5, 236, 414.5),
		92.0,
	],
	Type.NUT: [
		"res://assets/images/repairables/nut.png",
		Rect2(954, 265.5, 173.5, 185.5),
		58.0,
	],
}

@export var type := Type.GEAR
## The part's own outline, an Area2D with polygon or shape
## children tracing the art. It carries no collision state
## of its own: the part switches its layers and monitoring
## off at ready and tests points against it by hand, so it
## never shows up in the hand's physics picking.
@export var shape: Area2D

## True once the part sits in its socket. An installed part no longer
## follows the pointer.
var is_installed := false
## True while the part is hidden inside a drawer. It appears when
## that drawer opens.
var is_stored := false
## The drawer the part is stored in, or its last drawer while it is
## out on the bench. -1 when it has never been stored.
var drawer_index := -1
## Where this part rests inside its drawer for the current item,
## in the drawer's interior-local coordinates (see
## `Drawer.get_interior_local_rect()`), and the turn it rests at.
## The level chooses both when it restocks for an item, spaced so
## drawer-mates do not pile up, and the drawer goes back to this
## same spot and turn every time it opens for that item.
## `Vector2.INF` while the part has no spot yet.
var drawer_spot_local := Vector2.INF
var drawer_spot_rotation := 0.0
## True while a drawer is putting the part away. A returning part
## cannot be grabbed.
var is_returning := false
## True once the messy-desk charge has counted this part for
## an item that shipped (see `Level.charge_messy_desk()`).
var is_charged := false


## True once the level has chosen this part's drawer spot for
## the current item (see `drawer_spot_local`).
func has_drawer_spot() -> bool:
	return drawer_spot_local != Vector2.INF

var _shake_tween: Tween
var _turn_tween: Tween
var _hint_hint: OutlineHint
var _outlined_sprite: Sprite2D
var _sprite_material_before_hint: Material
var _is_hint_active := false


func _ready() -> void:
	_configure_shape()
	DropShadow.attach_silhouette(
		self,
		[get_node("%Art"), get_node("%Sprite")],
		Vector2(0.0, 6.0),
		func() -> bool:
			return (
				not is_installed
				and not is_stored
				and not is_returning
				and is_instance_valid(G.level)
				and is_instance_valid(G.level.hand)
				and G.level.hand.held != self
			),
		0.8,
		true,
	)


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


## True when the part has a usable authored Shape: a polygon
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


## True when a world point lands on the part's Shape: any
## of its polygons, or inside any of its collision shapes.
## False when the part has no Shape configured.
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
## and hints that want the part's real outline.
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


## How far the part reaches from its middle, in world pixels.
## The level keeps this much of the part inside the workable
## area when it comes to rest, and it sets how much the part
## bounces and skids when it lands there. The authored Shape
## wins when it has one; the drawn sprite and then the code
## polygon are the fallbacks.
func get_radius_px() -> float:
	var shape_points := get_shape_world_polygon()
	if shape_points.size() >= 3:
		var shape_radius := 0.0
		for point in shape_points:
			shape_radius = maxf(
				shape_radius,
				point.distance_to(global_position),
			)
		return shape_radius
	var sprite := get_node("%Sprite") as Sprite2D
	if is_instance_valid(sprite) and sprite.visible:
		var rect := sprite.get_rect()
		var radius := 0.0
		for corner in [
			rect.position,
			rect.end,
			Vector2(rect.position.x, rect.end.y),
			Vector2(rect.end.x, rect.position.y),
		]:
			radius = maxf(radius, (corner * sprite.scale).length())
		return radius
	var radius := 0.0
	for point in get_polygon(type):
		radius = maxf(radius, point.length())
	return radius


## The level starts bringing this part back to the workable
## area. Until `finish_bench_return()` the part cannot be
## grabbed, which `is_returning` already says for a part on
## its way into a drawer.
func start_bench_return() -> void:
	is_returning = true
	_stop_turn()
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	%Art.position = Vector2.ZERO


## The sound of the part hitting the bench, played by the
## level at its first bounce, not when it comes to rest.
func play_landing_sound() -> void:
	G.audio.play_sound(&"part_drop_large")


## The part has come to rest inside the workable area.
func finish_bench_return() -> void:
	is_returning = false
	# A part that is out stays in front of the drawers.
	z_index = 16


## True when this kind has real art (see `_ART`).
static func has_art(part_type: Type) -> bool:
	return _ART.has(part_type)


## Puts a kind's real art on a sprite, at its bench size. The kind must
## have art (`has_art()`).
static func apply_art(sprite: Sprite2D, part_type: Type) -> void:
	var entry: Array = _ART[part_type]
	var region := entry[1] as Rect2
	sprite.texture = load(entry[0] as String) as Texture2D
	sprite.region_enabled = true
	sprite.region_rect = region
	var longer_side := maxf(region.size.x, region.size.y)
	var bench_px := entry[2] as float
	sprite.scale = Vector2.ONE * (bench_px / longer_side)


## Sets the part's kind and its art: the real texture where
## the kind has one, the placeholder polygon where it doesn't.
func setup(part_type: Type) -> void:
	type = part_type
	%Art.polygon = get_polygon(part_type)
	%Art.color = get_color(part_type)
	var sprite := get_node("%Sprite") as Sprite2D
	if _ART.has(part_type):
		apply_art(sprite, part_type)
		sprite.show()
		%Art.hide()
	else:
		sprite.hide()
		%Art.show()


## The wrong socket, or a press that fits nowhere. No penalty.
func nope() -> void:
	G.audio.play_sound(&"clunk")
	G.audio.play_sound(&"hmm_grumpy")
	G.level.hand.show_nope(global_position)
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var step_sec := G.settings.nope_shake_sec / (_NOPE_SHAKE_STEPS + 1)
	for step in _NOPE_SHAKE_STEPS:
		var direction := 1.0 if step % 2 == 0 else -1.0
		_shake_tween.tween_property(
			%Art,
			"position",
			Vector2(direction * G.settings.nope_shake_px, 0.0),
			step_sec,
		)
	_shake_tween.tween_property(%Art, "position", Vector2.ZERO, step_sec)


## Shows or hides the idle hint outline on this part. It goes
## over the sprite: a kind with real art gets the shader outline
## on its sprite, the way a layer's does; only a kind still on
## its placeholder art gets the drawn rim, over that art. The
## tracker highlights a stored part's drawer instead, and this
## part once it is out on the bench.
func set_hint_active(is_active: bool) -> void:
	_is_hint_active = is_active
	if is_active:
		_start_hint()
	elif is_instance_valid(_hint_hint):
		_hint_hint.set_active(false)
	if not is_active and is_instance_valid(_outlined_sprite):
		OutlineHint.remove_from_sprite(
			_outlined_sprite, _sprite_material_before_hint
		)
		_outlined_sprite = null
		_sprite_material_before_hint = null


func _start_hint() -> void:
	var sprite := get_node("%Sprite") as Sprite2D
	if (
		is_instance_valid(sprite)
		and sprite.visible
		and is_instance_valid(sprite.texture)
	):
		if not is_instance_valid(_outlined_sprite):
			_outlined_sprite = sprite
			_sprite_material_before_hint = (
				OutlineHint.apply_to_sprite(sprite)
			)
		if is_instance_valid(_hint_hint):
			_hint_hint.set_active(false)
		return
	if not is_instance_valid(_hint_hint):
		_hint_hint = OutlineHint.new()
		add_child(_hint_hint)
		_hint_hint.polygon = OutlineHint.get_art_polygon(
			get_node("%Art")
		)
	_hint_hint.set_active(true)


## True while the idle hint outline shows on this part.
func is_hint_active() -> bool:
	if not _is_hint_active:
		return false
	if is_instance_valid(_outlined_sprite):
		return true
	return (
		is_instance_valid(_hint_hint) and _hint_hint.is_active()
	)


## The player picked this loose part up, from a drawer or the
## bench. It turns a bit in the fingers.
func on_picked_up() -> void:
	_turn_a_bit()


## The player set this part down on the bench, not into a socket
## or a drawer. It turns a bit as it lands.
func on_set_down() -> void:
	_turn_a_bit()


## Turns the part a little either way, over `_TURN_SEC`. Every
## turn moves at least `_TURN_MIN_RAD`, so it always reads.
func _turn_a_bit() -> void:
	if is_installed:
		return
	_stop_turn()
	var direction := 1.0 if randf() < 0.5 else -1.0
	var target_rotation := (
		rotation
		+ direction * randf_range(_TURN_MIN_RAD, _TURN_MAX_RAD)
	)
	_turn_tween = create_tween()
	_turn_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_turn_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_turn_tween.tween_property(
		self, "rotation", target_rotation, _TURN_SEC
	)


func _stop_turn() -> void:
	if is_instance_valid(_turn_tween):
		_turn_tween.kill()
	_turn_tween = null


## Leaves the hand and snaps into a socket. It turns to the
## socket's own orientation instead of a set-down turn. The
## socket hears about it when the part lands.
func install_into(socket: PartSocket) -> void:
	_stop_turn()
	is_installed = true
	var from_global_position := global_position
	if G.level.hand.held == self:
		G.level.hand.release()
	# Installed, it layers with the item again: the cover can close
	# over it. While held it stays on top (part.tscn's z_index).
	z_index = 0
	z_as_relative = true
	reparent(socket)
	global_position = from_global_position
	reset_physics_interpolation()
	G.audio.play_sound(&"rattle_snap")
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		self, "global_position", socket.global_position, _FIT_SEC
	)
	tween.parallel().tween_property(self, "rotation", 0.0, _FIT_SEC)
	tween.tween_callback(socket.on_part_installed)


static func get_display_name(part_type: Type) -> String:
	match part_type:
		Type.GEAR:
			return "Gear"
		Type.TUBE:
			return "Tube"
		Type.TV_CONTROLS:
			return "TV controls"
		Type.LETTER_KEY:
			return "Letter key"
		Type.SPACEBAR:
			return "Spacebar"
		Type.LED:
			return "LED"
		Type.JOYSTICK:
			return "Joystick"
		Type.CIRCUIT:
			return "Circuit"
		Type.CRYSTAL:
			return "Crystal"
		Type.BOLT:
			return "Bolt"
		Type.NUT:
			return "Nut"
		_:
			G.fatal()
			return ""


static func get_color(part_type: Type) -> Color:
	match part_type:
		Type.GEAR:
			return Color(0.85, 0.65, 0.2)
		Type.TUBE:
			return Color(0.45, 0.65, 0.85)
		Type.TV_CONTROLS:
			return Color(0.75, 0.45, 0.3)
		Type.LETTER_KEY:
			return Color(0.9, 0.88, 0.8)
		Type.SPACEBAR:
			return Color(0.85, 0.83, 0.75)
		Type.LED:
			return Color(0.95, 0.3, 0.25)
		Type.JOYSTICK:
			return Color(0.8, 0.25, 0.25)
		Type.CIRCUIT:
			return Color(0.25, 0.65, 0.35)
		Type.CRYSTAL:
			return Color(0.9, 0.35, 0.9)
		Type.BOLT:
			return Color(0.6, 0.62, 0.68)
		Type.NUT:
			return Color(0.7, 0.68, 0.6)
		_:
			G.fatal()
			return Color.WHITE


## A simple shape per kind, about 40 px across. Real art replaces
## these polygons later (LX24).
static func get_polygon(part_type: Type) -> PackedVector2Array:
	match part_type:
		Type.GEAR:
			var points := PackedVector2Array()
			for index in 16:
				var angle := TAU * index / 16.0
				var radius := 19.0 if index % 2 == 0 else 13.5
				points.append(Vector2.from_angle(angle) * radius)
			return points
		Type.TUBE:
			return PackedVector2Array(
				[
					Vector2(-20, -9),
					Vector2(20, -9),
					Vector2(20, 9),
					Vector2(-20, 9),
				]
			)
		Type.BOLT:
			return PackedVector2Array(
				[
					Vector2(-8, -20),
					Vector2(8, -20),
					Vector2(8, -6),
					Vector2(4, -6),
					Vector2(4, 20),
					Vector2(-4, 20),
					Vector2(-4, -6),
					Vector2(-8, -6),
				]
			)
		Type.NUT:
			var nut_points := PackedVector2Array()
			for index in 6:
				var angle := TAU * index / 6.0
				nut_points.append(Vector2.from_angle(angle) * 15.0)
			return nut_points
		Type.TV_CONTROLS:
			return PackedVector2Array(
				[
					Vector2(-14, -18),
					Vector2(14, -18),
					Vector2(14, 18),
					Vector2(-14, 18),
				]
			)
		Type.LETTER_KEY:
			return PackedVector2Array(
				[
					Vector2(-13, -13),
					Vector2(13, -13),
					Vector2(13, 13),
					Vector2(-13, 13),
				]
			)
		Type.SPACEBAR:
			return PackedVector2Array(
				[
					Vector2(-26, -8),
					Vector2(26, -8),
					Vector2(26, 8),
					Vector2(-26, 8),
				]
			)
		Type.LED:
			var led_points := PackedVector2Array()
			for index in 12:
				var angle := TAU * index / 12.0
				led_points.append(Vector2.from_angle(angle) * 11.0)
			return led_points
		Type.JOYSTICK:
			return PackedVector2Array(
				[
					Vector2(-6, -20),
					Vector2(6, -20),
					Vector2(6, 2),
					Vector2(16, 2),
					Vector2(16, 14),
					Vector2(-16, 14),
					Vector2(-16, 2),
					Vector2(-6, 2),
				]
			)
		Type.CIRCUIT:
			return PackedVector2Array(
				[
					Vector2(-20, -13),
					Vector2(20, -13),
					Vector2(20, 13),
					Vector2(-20, 13),
				]
			)
		Type.CRYSTAL:
			return PackedVector2Array(
				[
					Vector2(0, -17),
					Vector2(14, 0),
					Vector2(0, 17),
					Vector2(-14, 0),
				]
			)
		_:
			G.fatal()
			return PackedVector2Array()
