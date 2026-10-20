class_name PartSocket
extends InteractionPoint
## A spot where one kind of part belongs (docs/design/parts_bin.md).
##
## A broken part starts in it. The empty hand wiggles that part out,
## and then a press with the right part from the drawer snaps the new
## part in. While a part can be tugged, two arrows beside it pulse
## back and forth to suggest the wiggle. Dragging back and forth
## loosens it, and a single tap counts as one swing too, so a
## series of taps works it out.


## How far the broken part slides out as it loosens, in pixels.
const _MAX_SLIDE_OUT_PX := 8.0
## How far the broken part shifts sideways per radian it rocks.
const _ROCK_SHIFT_PX := 20.0
## How far above the part the yank arrows float while it is
## being tugged, in world pixels, like the glue hold's ring.
## They only show mid-tug, and they keep world size and
## heading whatever the item's scale and turn.
const _INDICATOR_OFFSET_PX := 88.0
const _INDICATOR_HALF_SPAN_PX := 30.0
## How long the popped scrap's flight off screen takes.
const _FLING_SEC := 0.55
## How far above where it came loose the scrap exits.
const _FLING_UP_PX := 420.0
## How far past the viewport edge the scrap flies before it goes.
const _FLING_MARGIN_PX := 160.0
## How far the scrap spins on its way out, in radians.
const _FLING_SPIN_RAD := 9.0

## The part kind this socket takes.
@export var accepted_part := Part.Type.GEAR
## Swings that wiggle the broken part out.
@export var swings_needed := 6
## Travel in screen pixels before a reversal counts as a swing.
@export var swing_min_px := 12.0
## False for a socket that starts empty.
@export var starts_with_broken_part := true
## Optional art of the fitted part, shown when a part lands
## (the TV's good controls, a piano's good LED). The drawer
## part itself is a small placeholder shape; this sprite is
## the real fitted piece at scene scale. Hidden until then.
@export var installed_art: Node2D
## Optional fastener that locks this socket while it is
## fastened (the Atari's stick is screwed down through its
## base tab). The broken part cannot be tugged, and the
## yank arrows stay hidden, until that fastener comes out.
## When the new part lands, the fastener goes into install
## mode so it can be driven back in to finish the item.
@export var locking_fastener: InteractionPoint
## Optional. Grime covering this socket. While it is not FINISHED the
## broken part can't be tugged out.
@export var covering_grime: GrimeSpot
## Optional outline of the broken part as it sits in the socket:
## an Area2D with polygon or shape children, the way a part's own
## Shape is authored. The empty hand can grab the broken part
## anywhere inside it, not just on the socket's own circle, and
## the hint follows it while the broken part sits here. It carries
## no collision state of its own: the socket strips it at ready
## and tests points against it by hand.
@export var bad_part_shape: Area2D
## Optional outline of the fitted part, the good one from the
## drawer, as it sits in the socket. A drop of that part is judged
## against it, and the hint and ghost outline follow it once the
## socket is empty. Set up the same way as `bad_part_shape`.
@export var good_part_shape: Area2D
## Whether the empty socket shows the ghost outline of the
## fitted part. Off where the fitted part stands proud of
## the item (the Atari's stick): the filled silhouette reads
## as a phantom part floating off the base, and the gap in
## the base art already says where the part goes.
@export var shows_ghost_outline := true

## True while the broken part still sits in the socket.
var has_broken_part := false

var _wiggle := Wiggle.new()
var _is_wiggling := false
var _last_pointer_screen_position := Vector2.ZERO
var _broken_part_home_position := Vector2.ZERO
var _pop_tween: Tween
var _settle_tween: Tween
var _press_swings := 0
var _yank_indicator: Node2D
var _yank_left: Polygon2D
var _yank_right: Polygon2D
var _yank_time := 0.0


func _ready() -> void:
	super._ready()
	_configure_shape_area(bad_part_shape)
	_configure_shape_area(good_part_shape)
	type = Type.PART_SOCKET
	has_broken_part = starts_with_broken_part
	%BrokenArt.polygon = Part.get_polygon(accepted_part)
	%BrokenArt.color = Part.get_color(accepted_part).darkened(0.45)
	# A kind with real art shows it, darkened, unless the scene gives the
	# broken part its own art (a sprite already under the broken
	# part, like the piano's busted LED): that art wins, and no
	# generated sprite is added over it.
	var has_own_broken_art := false
	for child in %BrokenPart.get_children():
		if child is Sprite2D:
			has_own_broken_art = true
	if has_own_broken_art:
		%BrokenArt.hide()
	elif %BrokenArt.visible and Part.has_art(accepted_part):
		var broken_sprite := Sprite2D.new()
		Part.apply_art(broken_sprite, accepted_part)
		# Where the scene authors the fitted sprite, the broken
		# one sits exactly where it will sit once fitted: the
		# fitted sprite's transform is in this item's own units,
		# where the bench size `apply_art()` used is in world
		# pixels. On a scaled item (the TV at 0.13) the bench
		# size alone shrank the broken controls to a postage
		# stamp beside the panel they belong on.
		if installed_art is Sprite2D:
			var fitted := installed_art as Sprite2D
			var broken_part := %BrokenPart as Node2D
			broken_sprite.transform = (
				broken_part.transform.affine_inverse()
				* fitted.transform
			)
			broken_sprite.centered = fitted.centered
			broken_sprite.offset = fitted.offset
			broken_sprite.flip_h = fitted.flip_h
			broken_sprite.flip_v = fitted.flip_v
		broken_sprite.modulate = Color.WHITE.darkened(0.45)
		%BrokenPart.add_child(broken_sprite)
		%BrokenArt.hide()
	%BrokenPart.visible = has_broken_part
	# The ghost outline traces the part's real art, not its
	# placeholder polygon: the polygon is tens of pixels across
	# where the fitted stick stands well over a hundred, so the
	# outline all but vanished against the real thing.
	var good_outline := _get_shape_area_local_polygon(good_part_shape)
	%Outline.polygon = (
		good_outline
		if good_outline.size() >= 3
		else _get_art_outline_points()
	)
	%Outline.scale = Vector2.ONE
	# The ghost only shows once the socket is empty: while
	# the broken part sits here it would draw a phantom of
	# the good part over it (the Atari's second stick).
	%Outline.visible = not has_broken_part and shows_ghost_outline
	if is_instance_valid(installed_art):
		installed_art.hide()
	_broken_part_home_position = %BrokenPart.position
	_build_yank_indicator()
	_refresh_yank_indicator()


func _process(delta: float) -> void:
	_refresh_yank_indicator()
	if not is_instance_valid(_yank_indicator) or not _yank_indicator.visible:
		return
	_place_yank_indicator()
	_yank_time += delta
	var wave := sin(_yank_time * TAU * 2.5)
	if is_instance_valid(_yank_left):
		_yank_left.modulate.a = 0.35 + 0.65 * maxf(wave, 0.0)
		_yank_left.scale = Vector2.ONE * (1.0 + 0.2 * maxf(wave, 0.0))
	if is_instance_valid(_yank_right):
		_yank_right.modulate.a = 0.35 + 0.65 * maxf(-wave, 0.0)
		_yank_right.scale = Vector2.ONE * (1.0 + 0.2 * maxf(-wave, 0.0))


## True while the back-and-forth yank arrows show.
func is_yank_indicator_visible() -> bool:
	return (
		is_instance_valid(_yank_indicator) and _yank_indicator.visible
	)


## True while the locking fastener still holds this socket down.
func is_locked() -> bool:
	return (
		is_instance_valid(locking_fastener)
		and locking_fastener.is_fastened()
	)


## True while grime covers this socket and has not been cleaned off.
func is_covered() -> bool:
	return (
		is_instance_valid(covering_grime)
		and covering_grime.mode != Mode.FINISHED
	)


## True while the item itself seals this socket (the shrink
## ray's crystal cannot be pulled until the ray has fired).
## The item sets and clears it; nothing else writes it.
var is_sealed := false


## True while a broken part sits here for the hand to tug out.
func has_tuggable_part() -> bool:
	return (
		has_broken_part
		and mode != Mode.FINISHED
		and not is_locked()
		and not is_covered()
		and not is_sealed
	)


## True while the player is mid-tug on the broken part.
func is_tugging() -> bool:
	return _is_wiggling


## True when a world point lands on the broken part's authored
## shape. False when the socket has no bad part shape (or it
## went away with the broken part it was parented under).
func is_point_in_bad_part_shape(world_point: Vector2) -> bool:
	return (
		is_instance_valid(bad_part_shape)
		and _is_point_in_shape_area(bad_part_shape, world_point)
	)


## True when a world point lands on the fitted part's authored
## shape. False when the socket has no good part shape.
func is_point_in_good_part_shape(world_point: Vector2) -> bool:
	return (
		is_instance_valid(good_part_shape)
		and _is_point_in_shape_area(good_part_shape, world_point)
	)


## True when a world point lands on either authored part shape.
func is_point_in_part_shape(world_point: Vector2) -> bool:
	return (
		is_point_in_bad_part_shape(world_point)
		or is_point_in_good_part_shape(world_point)
	)


## True when a world point lands on the part as it sits (or
## would sit) in this socket: the authored part shapes, or
## the fitted art's footprint, which the ghost outline
## already traces. Grabs and drops are judged against this,
## not just the socket's hit circle: that circle is authored
## in the item's units, so on a scaled item (the keyboard
## at 0.13) it is a few world pixels across, and a new key
## dropped on its outline missed by a mile.
func is_point_on_part(world_point: Vector2) -> bool:
	if is_point_in_part_shape(world_point):
		return true
	var polygon := _get_hint_polygon()
	if polygon.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(
		to_local(world_point), polygon
	)


## The bad part shape's first polygon, in world points.
func get_bad_part_world_polygon() -> PackedVector2Array:
	if not is_instance_valid(bad_part_shape):
		return PackedVector2Array()
	return _get_shape_area_world_polygon(bad_part_shape)


## The good part shape's first polygon, in world points.
func get_good_part_world_polygon() -> PackedVector2Array:
	if not is_instance_valid(good_part_shape):
		return PackedVector2Array()
	return _get_shape_area_world_polygon(good_part_shape)


## The empty hand pressed the socket. A broken part starts wiggling.
## An empty socket just rattles.
func on_poked() -> void:
	if has_tuggable_part():
		_is_wiggling = true
		_set_yank_highlight(true)
		if is_instance_valid(_settle_tween):
			_settle_tween.kill()
		%BrokenPart.position = _broken_part_home_position
		%BrokenPart.rotation = 0.0
		_last_pointer_screen_position = (
			G.level.hand.pointer_screen_position
		)
		# Swings banked by earlier taps survive this press, so
		# a series of taps adds up the way a drag does.
		var banked_swings := _wiggle.swings
		_wiggle.reset(
			_last_pointer_screen_position, swings_needed, swing_min_px
		)
		_wiggle.swings = banked_swings
		_press_swings = banked_swings
		_apply_wiggle_pose()
		G.level.hand.set_input_owner(self)
		G.audio.play_sound(&"creak")
	else:
		super.on_poked()


## A finger can land anywhere, so motion counts from the new press.
func on_pointer_pressed(_global_position: Vector2) -> void:
	_last_pointer_screen_position = G.level.hand.pointer_screen_position


func on_pointer_moved(_global_position: Vector2) -> void:
	if not _is_wiggling:
		return
	var pointer_position := G.level.hand.pointer_screen_position
	var swings_before := _wiggle.swings
	var is_out := _wiggle.feed(pointer_position)
	if is_out:
		_pop_out()
		return
	_apply_wiggle_pose()
	if _wiggle.swings != swings_before:
		G.audio.play_sound(&"ratchet", true)


func on_pointer_released(_global_position: Vector2) -> void:
	if _is_wiggling and _wiggle.swings == _press_swings:
		# A press that never dragged is a tap: one swing, in
		# the alternating direction, as though dragged that way.
		if _wiggle.tap_swing():
			_pop_out()
			return
		_apply_wiggle_pose()
		G.audio.play_sound(&"ratchet", true)
	_end_wiggle()


## True when this socket would take `part` right now: empty,
## unfinished, and the part is its kind. A drop judged by the
## part's own middle (see `Hand._drop_loose_part()`) only
## claims sockets this is true for, so dragging a part across
## the item on the way to a drawer never installs or nopes it.
func can_fit(part: Part) -> bool:
	return (
		mode != Mode.FINISHED
		and not has_broken_part
		and part.type == accepted_part
	)


## A press with a held part. Returns true when the press was used:
## the right part installs, anything else nopes and stays in hand.
func try_fit(part: Part) -> bool:
	if mode == Mode.FINISHED or has_broken_part:
		part.nope()
		return true
	if part.type != accepted_part:
		part.nope()
		return true
	part.install_into(self)
	return true


## The new part landed. The socket is done.
func on_part_installed() -> void:
	%Outline.visible = false
	_refresh_yank_indicator()
	if is_instance_valid(installed_art):
		installed_art.show()
		# The fitted sprite is the part as the item's own art
		# draws it, at the item's scale and spot. The drawer
		# part that just landed keeps its bench size and sits
		# centred on the socket, so leaving it drawn shows the
		# piece twice, offset (the Atari's two sticks).
		for child in get_children():
			if child is Part:
				(child as Part).hide()
	G.audio.play_sound(&"rattle_snap")
	# The locking fastener goes back in over the new part,
	# so it must count as unfinished again before this
	# socket's finish can finish the item.
	if is_instance_valid(locking_fastener):
		locking_fastener.set_install_mode()
	finish()


## The hint outline follows the fitted art too, not the
## socket's small hit circle. An authored part shape hugs the
## art closer still: the broken part's while it sits here, the
## fitted part's once it is out.
func _get_hint_polygon() -> PackedVector2Array:
	var shape_area := (
		bad_part_shape if has_broken_part else good_part_shape
	)
	var shaped := _get_shape_area_local_polygon(shape_area)
	if shaped.size() >= 3:
		return shaped
	var points := _get_art_outline_points()
	if points.size() >= 3:
		return points
	return super._get_hint_polygon()


## Where this socket's part sits, as a rectangle in socket
## space traced from the real art: the fitted sprite when the
## scene gives one, the broken part's sprite otherwise, grown
## a touch so the line clears the art. Kinds with neither
## keep the placeholder polygon, a little larger than the
## part, as before.
func _get_art_outline_points() -> PackedVector2Array:
	var rect := Rect2()
	var has_rect := false
	if installed_art is Sprite2D:
		var fitted := installed_art as Sprite2D
		rect = fitted.transform * fitted.get_rect()
		has_rect = true
	else:
		# The broken part flies off as scrap when it pops out,
		# so it may be gone by the time a hint asks.
		var broken_part := get_node_or_null("%BrokenPart") as Node2D
		if is_instance_valid(broken_part):
			for child in broken_part.get_children():
				if child is Sprite2D:
					var broken := child as Sprite2D
					rect = (
						broken_part.transform
						* broken.transform
						* broken.get_rect()
					)
					has_rect = true
					break
	if not has_rect:
		var points := Part.get_polygon(accepted_part)
		var scaled := PackedVector2Array()
		for point in points:
			scaled.append(point * 1.2)
		return scaled
	rect = rect.grow(4.0)
	return PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]
	)


## Builds the two yank arrows in code, one each side.
func _build_yank_indicator() -> void:
	_yank_indicator = Node2D.new()
	_yank_indicator.name = "YankIndicator"
	_yank_indicator.z_index = 20
	add_child(_yank_indicator)
	_yank_left = Polygon2D.new()
	_yank_left.name = "YankLeft"
	_yank_left.polygon = PackedVector2Array(
		[Vector2(6, -7), Vector2(-6, 0), Vector2(6, 7)]
	)
	_yank_left.color = Color(1.0, 0.92, 0.4, 1.0)
	_yank_left.position = Vector2(-_INDICATOR_HALF_SPAN_PX, 0)
	_yank_indicator.add_child(_yank_left)
	_yank_right = Polygon2D.new()
	_yank_right.name = "YankRight"
	_yank_right.polygon = PackedVector2Array(
		[Vector2(-6, -7), Vector2(6, 0), Vector2(-6, 7)]
	)
	_yank_right.color = Color(1.0, 0.92, 0.4, 1.0)
	_yank_right.position = Vector2(_INDICATOR_HALF_SPAN_PX, 0)
	_yank_indicator.add_child(_yank_right)


## The arrows show only while the part is being tugged:
## never as an idle hint beforehand, and they hide once it
## is out or fitted.
func _refresh_yank_indicator() -> void:
	if is_instance_valid(_yank_indicator):
		_yank_indicator.visible = _is_wiggling


## Floats the arrows above the part in world terms: the
## offset, size and heading stay the screen's, whatever
## scale and turn the item gives this socket.
func _place_yank_indicator() -> void:
	var inverse := global_transform.affine_inverse()
	_yank_indicator.position = inverse.basis_xform(
		Vector2(0.0, -_INDICATOR_OFFSET_PX)
	)
	_yank_indicator.rotation = -global_rotation
	var world_scale := global_transform.get_scale()
	_yank_indicator.scale = Vector2(
		1.0 / maxf(absf(world_scale.x), 0.001),
		1.0 / maxf(absf(world_scale.y), 0.001),
	)


## The broken part pops out and flies off as scrap. A hard
## yank (one long drag) pulls it out the same way, free: the
## socket is empty either way and no defect is charged.
func _pop_out() -> void:
	has_broken_part = false
	%Outline.visible = shows_ghost_outline
	_refresh_yank_indicator()
	_stop_wiggle()
	G.audio.play_sound(&"lid_pop", true)
	%BrokenPart.rotation = 0.0
	var scrap: Node2D = %BrokenPart
	var start_position := scrap.global_position
	scrap.reparent(G.level)
	scrap.reset_physics_interpolation()
	# Flung fast, up and off the nearest side of the viewport,
	# spinning, with no fade. It goes once it is past the edge.
	var canvas_inverse := get_canvas_transform().affine_inverse()
	var world_left := (canvas_inverse * Vector2.ZERO).x
	var world_right := (
		canvas_inverse * Vector2(get_viewport_rect().size.x, 0.0)
	).x
	var side := 1.0
	if start_position.x - world_left < world_right - start_position.x:
		side = -1.0
	var scrap_target := Vector2(
		(
			world_right + _FLING_MARGIN_PX
			if side > 0.0
			else world_left - _FLING_MARGIN_PX
		),
		start_position.y - _FLING_UP_PX,
	)
	if is_instance_valid(_pop_tween):
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_pop_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_pop_tween.tween_property(
		scrap, "global_position", scrap_target, _FLING_SEC
	)
	_pop_tween.parallel().tween_property(
		scrap, "rotation", side * _FLING_SPIN_RAD, _FLING_SEC
	)
	_pop_tween.tween_callback(scrap.queue_free)


## Rocks the broken part with the drag and slides it a tiny bit
## further out with each counted swing.
func _apply_wiggle_pose() -> void:
	var progress := 0.0
	if swings_needed > 0:
		progress = clampf(
			float(_wiggle.swings) / float(swings_needed), 0.0, 1.0
		)
	%BrokenPart.rotation = _wiggle.rock_angle_rad
	%BrokenPart.position = (
		_broken_part_home_position
		+ Vector2(
			_wiggle.rock_angle_rad * _ROCK_SHIFT_PX,
			-progress * _MAX_SLIDE_OUT_PX,
		)
	)


## The broken part's sprite while a yank highlights it, and
## the material it wore before (see `_set_yank_highlight()`).
var _yank_highlighted_sprite: Sprite2D
var _yank_sprite_material: Material


## Highlights the broken part while a yank is in progress,
## so what is being pulled reads at a glance. The shared
## outline material keeps it the same world width as every
## other sprite highlight.
func _set_yank_highlight(is_on: bool) -> void:
	if is_on:
		if is_instance_valid(_yank_highlighted_sprite):
			return
		var sprite := _get_broken_sprite()
		if not is_instance_valid(sprite):
			return
		_yank_highlighted_sprite = sprite
		_yank_sprite_material = OutlineHint.apply_to_sprite(sprite)
	else:
		if is_instance_valid(_yank_highlighted_sprite):
			OutlineHint.remove_from_sprite(
				_yank_highlighted_sprite, _yank_sprite_material
			)
		_yank_highlighted_sprite = null
		_yank_sprite_material = null


## The broken part's visible sprite, or null when the socket
## only has the placeholder polygon.
func _get_broken_sprite() -> Sprite2D:
	for child in %BrokenPart.get_children():
		if child is Sprite2D and (child as CanvasItem).visible:
			return child as Sprite2D
	return null


## Ends the wiggle's hold on the pointer, with no settle animation.
func _stop_wiggle() -> void:
	_is_wiggling = false
	_set_yank_highlight(false)
	if is_instance_valid(_settle_tween):
		_settle_tween.kill()
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)


func _end_wiggle() -> void:
	if not _is_wiggling:
		return
	_stop_wiggle()
	_settle_tween = create_tween()
	_settle_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_settle_tween.set_parallel()
	_settle_tween.tween_property(%BrokenPart, "rotation", 0.0, 0.1)
	_settle_tween.tween_property(
		%BrokenPart,
		"position",
		_broken_part_home_position,
		0.1,
	)
