class_name PartSocket
extends InteractionPoint
## A spot where one kind of part belongs (docs/design/parts_bin.md).
##
## A broken part starts in it. The empty hand wiggles that part out,
## and then a press with the right part from the drawer snaps the new
## part in.


## The part kind this socket takes.
@export var accepted_part := Part.Type.GEAR
## Swings that wiggle the broken part out.
@export var swings_needed := 4
## False for a socket that starts empty.
@export var starts_with_broken_part := true

## True while the broken part still sits in the socket.
var has_broken_part := false

var _wiggle := Wiggle.new()
var _is_wiggling := false
var _last_pointer_screen_position := Vector2.ZERO
var _pop_tween: Tween


func _ready() -> void:
	super._ready()
	type = Type.PART_SOCKET
	%Outline.polygon = Part.get_polygon(accepted_part)
	%Outline.scale = Vector2(1.2, 1.2)
	has_broken_part = starts_with_broken_part
	%BrokenArt.polygon = Part.get_polygon(accepted_part)
	%BrokenArt.color = Part.get_color(accepted_part).darkened(0.45)
	%BrokenPart.visible = has_broken_part


## The empty hand pressed the socket. A broken part starts wiggling.
## An empty socket just rattles.
func on_poked() -> void:
	if has_broken_part and mode != Mode.FINISHED:
		_is_wiggling = true
		_last_pointer_screen_position = (
			G.level.hand.pointer_screen_position
		)
		_wiggle.reset(_last_pointer_screen_position, swings_needed)
		G.level.hand.set_input_owner(self)
		G.audio.play_sound("creak")
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
	%BrokenPart.rotation = _wiggle.rock_angle_rad
	if _wiggle.swings != swings_before:
		G.audio.play_sound("ratchet", true)
	if is_out:
		_pop_out()


func on_pointer_released(_global_position: Vector2) -> void:
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
	G.audio.play_sound("click")
	finish()


## The broken part pops out and flies off as scrap. A yank costs a
## defect and still leaves the socket empty.
func _pop_out() -> void:
	var was_yanked := _wiggle.is_yanked
	has_broken_part = false
	_end_wiggle()
	G.audio.play_sound("pop", true)
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


func _end_wiggle() -> void:
	if not _is_wiggling:
		return
	_is_wiggling = false
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(%BrokenPart, "rotation", 0.0, 0.1)
