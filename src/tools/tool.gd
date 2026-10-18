class_name Tool
extends Node2D
## A tool on the bench. The hand picks it up, moves it and puts it back
## (docs/design/tools.md). While IN_USE, the point it engaged places it
## every frame, like a puppet.


enum Type {
	FLAT_HEAD_SCREW_DRIVER,
	RAG,
	AIR_BLOWER,
	HAMMER,
	GLUE,
}

enum Mode {
	ENTERING,
	STORED,
	HELD,
	IN_USE,
}

const ROTATE_DURATION_SEC := 0.3
const POSITION_DURATION_SEC := 0.3
## How many times the tool jerks in the "nope" shake.
const _NOPE_SHAKE_STEPS := 4

@export var type := Type.FLAT_HEAD_SCREW_DRIVER

## The tip: the point on the tool that stays under the pointer while
## held.
@export var cursor_position: Marker2D

## The area the hand finds when a press lands on the stored tool.
@export var grab_area: Area2D
## The area at the tool's working end.
@export var interaction_area: Area2D
## The area that lines up with the tool's holder.
@export var holder_area: Area2D

@export var stored_rotation_deg := 0.0
@export var held_rotation_deg := 0.0

var mode := Mode.ENTERING:
	set(to_mode):
		var from_mode := mode
		mode = to_mode
		_set_mode(to_mode, from_mode)

## The point using this tool while IN_USE, or null.
var engaged_point: InteractionPoint
## Added to the pointer while held. It eases to zero, so the tool glides
## into the hand instead of jumping (LX5).
var follow_offset := Vector2.ZERO

var position_tween: Tween
var rotation_tween: Tween

var _shake_offset := Vector2.ZERO
var _follow_offset_tween: Tween
var _shake_tween: Tween


func _ready() -> void:
	G.check(is_instance_valid(cursor_position))

	G.check(is_instance_valid(grab_area))
	G.check(grab_area.monitorable)
	G.check(grab_area.collision_layer == Settings.PhysicsLayer.TOOLS)

	G.check(is_instance_valid(interaction_area))
	G.check(
		(interaction_area.collision_mask
			& Settings.PhysicsLayer.INTERACTION_POINTS)
		== Settings.PhysicsLayer.INTERACTION_POINTS
	)

	G.check(is_instance_valid(holder_area))
	G.check(holder_area.monitoring)
	G.check(
		holder_area.collision_mask == Settings.PhysicsLayer.TOOL_HOLDERS
	)
	G.check(is_instance_valid(_get_holder_shape()))
	holder_area.area_entered.connect(_on_holder_area_entered)


func _physics_process(_delta: float) -> void:
	if mode == Mode.HELD:
		place_tip(
			G.level.hand.pointer_position + follow_offset + _shake_offset
		)


func _set_mode(to_mode: Mode, _from_mode: Mode) -> void:
	match to_mode:
		Mode.ENTERING, Mode.STORED:
			tween_rotation(deg_to_rad(stored_rotation_deg))
			tween_position(_get_stored_position())
		Mode.HELD:
			# The follow in _physics_process takes over the position.
			if is_instance_valid(position_tween):
				position_tween.kill()
			tween_rotation(deg_to_rad(held_rotation_deg))
		Mode.IN_USE:
			# The engaged point places the tool every frame.
			if is_instance_valid(position_tween):
				position_tween.kill()
		_:
			G.error()


## Called by the hand when it takes this tool.
func pick_up() -> void:
	var from_tip := get_tip_position()
	mode = Mode.HELD
	# Glide from the rack into the hand (LX5).
	ease_follow_offset_from(from_tip - G.level.hand.pointer_position)


## Sends the tool back to its holder and empties the hand if it held
## this tool.
func put_away() -> void:
	if is_instance_valid(G.level.hand) and G.level.hand.held == self:
		G.level.hand.release()
	engaged_point = null
	_cancel_follow_offset()
	mode = Mode.STORED


## Called by a point when it engages this tool. The point places the
## tool until it calls stop_use().
func start_use(point: InteractionPoint) -> void:
	engaged_point = point
	mode = Mode.IN_USE


## Called by a point when it finishes with or ejects this tool.
func stop_use() -> void:
	engaged_point = null
	if mode != Mode.IN_USE:
		return
	var from_tip := get_tip_position()
	mode = Mode.HELD
	# The tip may have drifted from the hidden pointer (LX5).
	ease_follow_offset_from(from_tip - G.level.hand.pointer_position)


## True for effect tools. They stay HELD and act where they press
## instead of engaging one point (docs/design/tools.md).
func is_effect_tool() -> bool:
	return false


## Called by the hand when a press lands while this effect tool is
## held. The tool acts at the press point. It may register as the
## hand's input owner to keep the drag and the release.
func on_effect_pressed(_global_point: Vector2) -> void:
	pass


## The press landed on a point that does not accept this tool. No
## penalty.
func nope() -> void:
	G.audio.play_sound(&"clunk")
	G.level.hand.show_nope(get_tip_position())
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var step_sec := G.settings.nope_shake_sec / (_NOPE_SHAKE_STEPS + 1)
	for step in _NOPE_SHAKE_STEPS:
		var direction := 1.0 if step % 2 == 0 else -1.0
		_shake_tween.tween_property(
			self,
			"_shake_offset",
			Vector2(direction * G.settings.nope_shake_px, 0.0),
			step_sec,
		)
	_shake_tween.tween_property(self, "_shake_offset", Vector2.ZERO, step_sec)


func get_tip_position() -> Vector2:
	return cursor_position.global_position


## Moves the tool so its tip is at a world position.
func place_tip(global_point: Vector2) -> void:
	global_position = global_point - (get_tip_position() - global_position)


## Puts the tip at a press point and drops any follow offset still
## easing out (tools.md rule 4).
func snap_tip_to(global_point: Vector2) -> void:
	_cancel_follow_offset()
	place_tip(global_point)


## Starts the follow offset at a value and eases it to zero.
func ease_follow_offset_from(offset: Vector2) -> void:
	_cancel_follow_offset()
	follow_offset = offset
	_follow_offset_tween = (
		create_tween()
		.set_trans(Tween.TRANS_QUAD)
		.set_ease(Tween.EASE_OUT)
	)
	_follow_offset_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_follow_offset_tween.tween_property(
		self,
		"follow_offset",
		Vector2.ZERO,
		G.settings.tool_follow_ease_sec,
	)


func tween_rotation(p_rotation: float, ease := Tween.EASE_IN_OUT) -> void:
	if is_instance_valid(rotation_tween):
		rotation_tween.kill()
	rotation_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(ease)
	rotation_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	rotation_tween.tween_property(
		self,
		"rotation",
		p_rotation,
		ROTATE_DURATION_SEC,
	)


func tween_position(
	p_global_position: Vector2,
	ease := Tween.EASE_IN_OUT,
) -> void:
	if is_instance_valid(position_tween):
		position_tween.kill()
	position_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(ease)
	position_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	position_tween.tween_property(
		self,
		"global_position",
		p_global_position,
		POSITION_DURATION_SEC,
	)


func _cancel_follow_offset() -> void:
	if is_instance_valid(_follow_offset_tween):
		_follow_offset_tween.kill()
	follow_offset = Vector2.ZERO


func _get_holder_shape() -> CollisionShape2D:
	for child in holder_area.get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null


## Where the tool's origin goes so that its holder shape sits on the
## holder at the stored rotation (LX4).
func _get_stored_position() -> Vector2:
	var shape_offset := _get_holder_shape().global_position - global_position
	# Undo the current rotation and apply the stored one.
	shape_offset = shape_offset.rotated(
		deg_to_rad(stored_rotation_deg) - global_rotation
	)
	return G.level.get_tool_holder_position(type) - shape_offset


func _on_holder_area_entered(area: Area2D) -> void:
	var holder := area as ToolHolder
	if not is_instance_valid(holder) or holder.type != type:
		return
	if mode == Mode.ENTERING or mode == Mode.HELD:
		put_away()
