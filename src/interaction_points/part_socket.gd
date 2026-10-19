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
	type = Type.PART_SOCKET
	%Outline.polygon = Part.get_polygon(accepted_part)
	%Outline.scale = Vector2(1.2, 1.2)
	has_broken_part = starts_with_broken_part
	%BrokenArt.polygon = Part.get_polygon(accepted_part)
	%BrokenArt.color = Part.get_color(accepted_part).darkened(0.45)
	%BrokenPart.visible = has_broken_part
	if is_instance_valid(installed_art):
		installed_art.hide()
	_broken_part_home_position = %BrokenPart.position
	_build_yank_indicator()
	_refresh_yank_indicator()


func _process(delta: float) -> void:
	if not is_instance_valid(_yank_indicator) or not _yank_indicator.visible:
		return
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


## True while a broken part sits here for the hand to tug out.
func has_tuggable_part() -> bool:
	return has_broken_part and mode != Mode.FINISHED


## True while the player is mid-tug on the broken part.
func is_tugging() -> bool:
	return _is_wiggling


## The empty hand pressed the socket. A broken part starts wiggling.
## An empty socket just rattles.
func on_poked() -> void:
	if has_tuggable_part():
		_is_wiggling = true
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
	G.audio.play_sound(&"click")
	finish()


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
	_yank_left.position = Vector2(-30, 0)
	_yank_indicator.add_child(_yank_left)
	_yank_right = Polygon2D.new()
	_yank_right.name = "YankRight"
	_yank_right.polygon = PackedVector2Array(
		[Vector2(-6, -7), Vector2(6, 0), Vector2(-6, 7)]
	)
	_yank_right.color = Color(1.0, 0.92, 0.4, 1.0)
	_yank_right.position = Vector2(30, 0)
	_yank_indicator.add_child(_yank_right)


## The arrows show while a part can be tugged, and hide
## once it is out or fitted.
func _refresh_yank_indicator() -> void:
	if is_instance_valid(_yank_indicator):
		_yank_indicator.visible = has_tuggable_part()


## The broken part pops out and flies off as scrap. A yank costs a
## defect and still leaves the socket empty.
func _pop_out() -> void:
	var was_yanked := _wiggle.is_yanked
	has_broken_part = false
	_refresh_yank_indicator()
	_stop_wiggle()
	G.audio.play_sound(&"pop", true)
	if was_yanked:
		var item := get_item()
		if is_instance_valid(item):
			item.quality.add_defect(
				RepairQuality.Defect.YANKED_PART,
				global_position,
				self,
			)
	%BrokenPart.rotation = 0.0
	var scrap: Node2D = %BrokenPart
	var scrap_target: Vector2 = scrap.global_position + Vector2(-260.0, 180.0)
	scrap.reparent(G.level)
	scrap.reset_physics_interpolation()
	if is_instance_valid(_pop_tween):
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_pop_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_pop_tween.tween_property(scrap, "global_position", scrap_target, 0.4)
	_pop_tween.parallel().tween_property(scrap, "rotation", 5.0, 0.4)
	_pop_tween.parallel().tween_property(scrap, "modulate:a", 0.0, 0.4)
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


## Ends the wiggle's hold on the pointer, with no settle animation.
func _stop_wiggle() -> void:
	_is_wiggling = false
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
