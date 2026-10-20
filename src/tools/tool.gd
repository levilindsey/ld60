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
	PHILLIPS_SCREW_DRIVER,
}

enum Mode {
	ENTERING,
	STORED,
	HELD,
	IN_USE,
}

## How this tool's shadow is drawn while it rests in its holder,
## picked from where the tool meets the holder at `holder_area`:
## the glue bottle sits on a shelf (an ellipse under the contact),
## and the hanging tools cast none. A tool also casts no
## shadow while it is held or in use.
enum HolderShadow {
	ELLIPSE_AT_HOLDER,
	SILHOUETTE,
	NONE,
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
## The in-holder shadow treatment for this tool (see HolderShadow).
## Set per tool scene: glue is ELLIPSE_AT_HOLDER, the rest
## are NONE.
@export var holder_shadow := HolderShadow.NONE

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
var _hint_hint: OutlineHint
var _is_hint_active := false
var _follow_offset_tween: Tween
var _shake_tween: Tween
var _drop_shadow: DropShadow
## True once the tip has been outside this tool's holder during
## the current hold, which arms putting it away by its tip.
var _tip_left_holder := false


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
	_drop_shadow = DropShadow.attach_silhouette(
		self,
		[],
		Vector2(0.0, 6.0),
		func() -> bool:
			return (
				holder_shadow != HolderShadow.NONE
				and (mode == Mode.ENTERING or mode == Mode.STORED)
			),
	)
	_update_drop_shadow()


func _physics_process(_delta: float) -> void:
	if mode == Mode.HELD:
		place_tip(
			G.level.hand.pointer_position + follow_offset + _shake_offset
		)
		_check_holder_return()


## Dragging the tip into this tool's own holder puts the tool
## away, like dragging its neck there already does. The tip must
## leave the holder first, so taking the tool off the rack (its
## tip starts beyond the holder) never puts it straight back.
func _check_holder_return() -> void:
	if not is_instance_valid(G.level):
		return
	if follow_offset.length() > 2.0:
		# Still gliding from the rack into the hand.
		return
	if _is_tip_over_own_holder():
		if _tip_left_holder:
			put_away()
	else:
		_tip_left_holder = true


## Whether the tip (the cursor position) is inside this tool's
## own ToolHolder area right now.
func _is_tip_over_own_holder() -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_tip_position()
	query.collision_mask = Settings.PhysicsLayer.TOOL_HOLDERS
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hits := get_world_2d().direct_space_state.intersect_point(
		query,
		4,
	)
	for hit in hits:
		var holder := hit.get("collider") as ToolHolder
		if is_instance_valid(holder) and holder.type == type:
			return true
	return false


## Points the drop shadow at the holder treatment this mode
## calls for. Held and in-use tools cast no shadow, so only the
## stored treatments are configured here. The shadow's own
## `show_when` hides it in the other modes.
func _update_drop_shadow() -> void:
	if not is_instance_valid(_drop_shadow):
		return
	match mode:
		Mode.ENTERING, Mode.STORED:
			match holder_shadow:
				HolderShadow.ELLIPSE_AT_HOLDER:
					_drop_shadow.anchor = holder_area
					_drop_shadow.size_px = Vector2(100.0, 24.0)
					_drop_shadow.offset_px = Vector2(0.0, -4.0)
					_drop_shadow.kind = DropShadow.Kind.ELLIPSE
				HolderShadow.SILHOUETTE:
					_drop_shadow.anchor = null
					_drop_shadow.offset_px = Vector2(0.0, 8.0)
					_drop_shadow.kind = DropShadow.Kind.SILHOUETTE
				HolderShadow.NONE:
					pass


func _set_mode(to_mode: Mode, _from_mode: Mode) -> void:
	_update_drop_shadow()
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
	G.audio.play_sound(&"tool_pickup")
	var from_tip := get_tip_position()
	_tip_left_holder = false
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
	# A soft knock when the glide lands it in its holder. A
	# glide cut short (picked straight back up) never lands.
	if is_instance_valid(position_tween):
		position_tween.finished.connect(
			_on_put_away_landed, CONNECT_ONE_SHOT
		)


## The put-away glide reached the holder.
func _on_put_away_landed() -> void:
	G.audio.play_sound(&"tool_set_down")


## Puts the tool straight into its holder, with no glide.
func snap_to_holder() -> void:
	put_away()
	if is_instance_valid(rotation_tween):
		rotation_tween.kill()
	if is_instance_valid(position_tween):
		position_tween.kill()
	rotation = deg_to_rad(stored_rotation_deg)
	global_position = _get_stored_position()
	reset_physics_interpolation()


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


## True when taking this tool off the rack with a press should
## also start its effect on that same press, so the drag that
## follows the pickup works at once. Only drag-acting tools
## (the rag) opt in: a tool that acts somewhere (the glue,
## the hammer, the blower) must wait for a press in the hand,
## or picking it up would fire it at the rack.
func acts_on_pickup() -> bool:
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
	G.audio.play_sound(&"hmm_grumpy")
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


## Shows or hides the idle hint outline around this tool, in the
## shape of its grab area. The tracker only lights a tool after
## the longer delay, and only while it rests stored in the rack.
func set_hint_active(is_active: bool) -> void:
	_is_hint_active = is_active
	if is_active:
		var points := _get_hint_polygon()
		if points.size() < 3:
			return
		if not is_instance_valid(_hint_hint):
			_hint_hint = OutlineHint.new()
			add_child(_hint_hint)
		_hint_hint.polygon = points
		_hint_hint.set_active(true)
	elif is_instance_valid(_hint_hint):
		_hint_hint.set_active(false)


## True while the idle hint outline shows on this tool.
func is_hint_active() -> bool:
	return (
		_is_hint_active
		and is_instance_valid(_hint_hint)
		and _hint_hint.is_active()
	)


func _get_hint_polygon() -> PackedVector2Array:
	if not is_instance_valid(grab_area):
		return PackedVector2Array()
	for child in grab_area.get_children():
		var local_points := PackedVector2Array()
		if child is CollisionShape2D:
			local_points = OutlineHint.get_shape_polygon(
				child as CollisionShape2D,
			)
		elif child is CollisionPolygon2D:
			local_points = (child as CollisionPolygon2D).polygon
		if local_points.size() < 3:
			continue
		var polygon_node := child as Node2D
		var points := PackedVector2Array()
		for point in local_points:
			points.append(to_local(polygon_node.to_global(point)))
		return points
	return PackedVector2Array()


func get_tip_position() -> Vector2:
	return cursor_position.global_position


## Moves the tool so its tip is at a world position.
func place_tip(global_point: Vector2) -> void:
	global_position = global_point - (get_tip_position() - global_position)


## The working end's world position: where this tool acts on a point.
## It is usually well away from the cursor marker, so engaging a point
## lines this up with the point, not the marker.
func get_work_end_position() -> Vector2:
	return interaction_area.global_position


## Moves the tool so its working end is at a world position.
func place_work_end(global_point: Vector2) -> void:
	global_position = global_point - (get_work_end_position() - global_position)


## The collision shape of the working end, the shape that must line
## up with a point's area to engage it.
func get_interaction_shape() -> CollisionShape2D:
	for child in interaction_area.get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null


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
