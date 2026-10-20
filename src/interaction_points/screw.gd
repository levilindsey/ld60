class_name Screw
extends InteractionPoint
## A screw: a FASTENER that holds its layer on until it comes out
## (docs/design/screws.md).
##
## A screw has health. Every slip of its driver costs 1, and at 0 it is
## stripped: the driver no longer bites. A seized screw won't turn until
## the oil can frees it. A screw shows how far in it is by turning its
## head and sliding its art up out of its hole (`slide`). It never scales.
##
## Once it is all the way out, it pulls itself out of the hole and
## comes to rest on the bench where it landed. The player drags it
## around the bench. When its layer is back on, dragging it close to
## its hole seats it: it arcs down into the hole, loose and ready to
## be driven in (docs/design/screw_pullout.md). Screws of a given
## type are interchangeable: it may instead seat into any other
## empty hole of its type on its layer, and the screw that hole
## belongs to takes this screw's hole in trade. The root stays at
## the hole with the hole art and the clip mask. Only the art and
## the hit shape move.
##
## Each screw type runs its own microgame. It overrides
## `_start_microgame()`, feeds `slide` as it turns the head, and calls
## `remove()` or `install()` once the head has turned all the way.


signal damaged(health: int)
signal stripped
signal removed
signal installed

## The head's look at each health, from the table in screws.md.
enum HeadFrame {
	CLEAN,
	SCRATCHED,
	CHEWED,
	STRIPPED,
}

## Where the screw is on its trip from its hole to the bench and back.
enum Travel {
	## In its hole. Only here can it be driven.
	HOME,
	## `pull_out_animation` plays from where the last twist left it.
	PULLING_OUT,
	## The bench art slides from the hole to the screw's rest spot.
	LEAVING,
	## Waiting at its rest spot on the bench.
	RESTING,
	## The bench art slides from the rest spot back over the hole.
	RETURNING,
	## `pull_out_animation` plays backwards: the screw sinks into its hole.
	SINKING,
}

## How far a loose screw's head sits turned back (counter-clockwise) from
## home: half a turn and a little more. The slot looks the same after half
## a turn, so the player sees a small turned-back angle, and driving the
## screw in turns it about half a turn clockwise.
const LOOSE_TURN_RAD := PI * 1.125

# Placeholder until LX24.
## Tints that stand in for the head frames' art, one per `HeadFrame`.
const _PLACEHOLDER_FRAME_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.85, 0.62),
	Color(0.95, 0.6, 0.38),
	Color(0.6, 0.28, 0.22),
]
## Seconds from the grind to the stand-in pry.
const _PRY_DELAY_SEC := 0.3
## Seconds a picked-up screw takes to turn in the fingers.
const _PICKUP_TURN_SEC := 0.25
## The most a picked-up screw turns either way, in radians.
const _PICKUP_MAX_TURN_RAD := PI / 4.0
## How long a short screw roll takes when set down after a
## drag (a long one takes longer, with the square root of its
## reach), and how far the head end sweeps while it rolls: from
## a nudge to a full swing across the bench.
const _ROLL_SEC := 0.55
const _ROLL_HEAD_MIN_PX := 16.0
const _ROLL_HEAD_MAX_PX := 150.0
## Release speed (px/s) above which a set-down roll follows the
## drag's motion instead of falling either way.
const _ROLL_FLING_MIN_SPEED := 60.0
## The head's centre, the tip, and the radii of both ends in the
## bench art's own texture pixels, measured from the art (both
## screw kinds share the drawing): the wide head is at the top,
## the pointy end at the bottom. The art's world scale turns
## these into pixels on the bench (head about 24 px across,
## shaft about 11, head to tip about 41).
const _HEAD_LOCAL := Vector2(9.5, -132)
const _TIP_LOCAL := Vector2(9.5, 502.5)
const _HEAD_RADIUS_LOCAL := 188
const _SHAFT_RADIUS_LOCAL := 86.75

## The screw head's art, seen from the top. The twists turn it. If it is an
## `AnimatedSprite2D`, its frames are the `HeadFrame` states in order.
@export var head: Node2D
## Health when the screw arrives. Each slip costs 1.
@export var max_health := 3
## A rusted screw won't turn until the oil can frees it (LX21).
@export var is_seized := false:
	set(value):
		is_seized = value
		if is_node_ready():
			_update_rust()
## Optional. Rust on the head, shown while seized.
@export var rust_overlay: CanvasItem
## Optional. A rust streak running down from the hole, shown while seized.
@export var rust_streak: CanvasItem
## Optional. Grime covering this screw. While it is not FINISHED the
## screw cannot be worked.
@export var covering_grime: GrimeSpot

@export_group("Pull-out")
## Plays `pull_out_animation`.
@export var animation_player: AnimationPlayer
## Pulls the screw out of its hole. Its first key for `slide_node`'s
## position is the backed-out pose, where the twists leave the screw
## (`slide` 1), so that key sets how far the twists raise it. Its last pose
## must match `bench_art`. It plays backwards to sink the screw back in.
@export var pull_out_animation := &"RemoveScrew"
## What the slide moves: the screw's art inside the clip mask. Where it
## sits in the scene is the screw all the way in.
@export var slide_node: Node2D
## Clips the screw's art to the part above the hole. It hides while the
## screw is out of its hole.
@export var clip_space: CanvasItem
## The screw out of its hole, unclipped, matching the end of
## `pull_out_animation`. It slides to the bench and back, and is hidden
## while the screw is in its hole.
@export var bench_art: Node2D
## The screw's hit shape. It slides with the art, and is off while the
## screw is out of its hole.
@export var hit_shape: CollisionShape2D
## A press this close to a resting screw's middle, in world pixels, is a
## press on it.
@export var rest_hit_radius_px := 22.0
## Where a resting screw's middle sits from `bench_art`'s origin.
@export var rest_hit_offset := Vector2(0.0, 10.0)
@export_group("")

## True once its layer was put back: the screw sits loose in its hole,
## turned back, and driving it in uses the same microgame.
var is_install_mode := false
var health := 0
## How far out of its hole the screw has slid: 0 is all the way in and 1 is
## the backed-out pose that starts `pull_out_animation`. The art and the
## hit shape slide straight up the screen, `get_slide_height_px()` at 1.
## Set it once the screw is ready.
var slide := 0.0:
	set(value):
		slide = clampf(value, 0.0, 1.0)
		_update_slide_position()
## Where the screw is on its trip from its hole to the bench and back.
var travel := Travel.HOME
## True while the hand is carrying this screw across the bench.
var is_carried := false
## True while the level is bringing this screw back to the
## workable area after it was dropped outside it. It cannot
## be picked up again until it comes to rest.
var is_returning := false

## The head's angle when the screw is all the way in.
var _home_head_rotation := 0.0
## Where `slide_node` and the hit shape sit at `slide` 0, and how far each
## moves at `slide` 1, in its own parent's frame.
var _home_slide_position := Vector2.ZERO
var _slide_offset := Vector2.ZERO
var _home_shape_position := Vector2.ZERO
var _shape_slide_offset := Vector2.ZERO
## Where `bench_art` sits under the screw, and its scale.
var _bench_art_home_position := Vector2.ZERO
var _bench_art_home_scale := Vector2.ONE
var _bench_art_home_rotation := 0.0
## The turn this screw was left at where it rests on the bench. A
## fresh one is picked each time it is set down.
var _rest_rotation := 0.0
## Where the bench art starts and ends its trip, in world pixels. A trip
## back ends over the hole wherever the screw is.
var _travel_from := Vector2.ZERO
var _travel_to := Vector2.ZERO
## True once a press on the stripped screw has ground and noped.
var _is_strip_warned := false
## True once the first try on the seized screw has ground as a warning.
var _is_seize_warned := false
var _pry_tween: Tween
var _travel_tween: Tween
var _rest_pulse_tween: Tween
var _pickup_tween: Tween
var _roll_tween: Tween
## The roll taken when the screw is set down after a drag: where
## it started, the fixed apex it rolls around, and its yaw.
var _roll_from_position := Vector2.ZERO
var _roll_from_rotation := 0.0
var _roll_apex := Vector2.ZERO
var _roll_angle_rad := 0.0
var _outlined_bench_art: Sprite2D
var _bench_material_before_outline: Material
var _is_rest_hint_active := false


func _init() -> void:
	role = Role.FASTENER


func _ready() -> void:
	super._ready()
	G.check(role == Role.FASTENER)
	G.check(is_instance_valid(head))
	G.check(max_health > 0)
	G.check(is_instance_valid(animation_player))
	G.check(animation_player.has_animation(pull_out_animation))
	G.check(is_instance_valid(slide_node))
	G.check(slide_node.get_parent() is Node2D)
	G.check(is_instance_valid(clip_space))
	G.check(is_instance_valid(bench_art))
	G.check(is_instance_valid(hit_shape))
	make_upright()
	_home_slide_position = slide_node.position
	_slide_offset = _get_backed_out_position() - _home_slide_position
	_home_shape_position = hit_shape.position
	var slide_frame := (
		global_transform.affine_inverse()
		* (slide_node.get_parent() as Node2D).global_transform
	)
	_shape_slide_offset = slide_frame.basis_xform(_slide_offset)
	_bench_art_home_position = bench_art.position
	_bench_art_home_scale = bench_art.scale
	_bench_art_home_rotation = bench_art.rotation
	bench_art.hide()
	animation_player.animation_finished.connect(_on_animation_finished)
	DropShadow.attach_silhouette(
		bench_art,
		[],
		Vector2(0.0, 3.0),
		func() -> bool:
			return (
				travel == Travel.RESTING
				and not is_carried
				and not is_returning
			),
		0.8,
		true,
	)
	health = max_health
	_update_head_frame()
	_update_rust()


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# The bench art is not a child while the screw is out of its hole.
	if is_instance_valid(bench_art) and bench_art.get_parent() != self:
		bench_art.queue_free()


## True while grime covers this screw and has not been cleaned off.
func is_covered() -> bool:
	return (
		is_instance_valid(covering_grime)
		and covering_grime.mode != Mode.FINISHED
	)


## A screw out of its hole can't be engaged. Neither can a covered one.
func can_engage() -> bool:
	return (
		travel == Travel.HOME
		and not is_covered()
		and super.can_engage()
	)


func is_fastened() -> bool:
	if is_install_mode:
		return mode == Mode.FINISHED
	return mode != Mode.FINISHED


func is_stripped() -> bool:
	return health <= 0


## The head frame for the current health: 3 or more is clean, 0 is
## stripped.
func get_head_frame() -> HeadFrame:
	return (
		HeadFrame.STRIPPED - clampi(health, 0, HeadFrame.STRIPPED)
	) as HeadFrame


## How far the art slides up the screen at `slide` 1, in world pixels.
func get_slide_height_px() -> float:
	var slide_parent := slide_node.get_parent() as Node2D
	return slide_parent.global_transform.basis_xform(_slide_offset).length()


## Moves the node's own rotation onto the head. A screw node's rotation
## only sets its slot's angle, so the art, the hole and the slide stay
## upright in the parent's frame. `_ready()` calls it, and so may a probe
## that turns a screw after that.
func make_upright() -> void:
	head.rotation += rotation
	rotation = 0.0
	_home_head_rotation = head.rotation
	reset_physics_interpolation()


## Costs health. Each point lost is a SCREW_DAMAGE defect, and the strip
## at 0 adds SCREW_STRIPPED on top.
func take_damage(amount := 1) -> void:
	var lost := mini(amount, health)
	if lost <= 0:
		return
	health -= lost
	for _point in lost:
		_add_defect(RepairQuality.Defect.SCREW_DAMAGE)
	_update_head_frame()
	damaged.emit(health)
	if is_stripped():
		_add_defect(RepairQuality.Defect.SCREW_STRIPPED)
		stripped.emit()


## Frees a seized screw, so it turns normally. The oil can calls it
## (LX21).
func unseize() -> void:
	is_seized = false
	_is_seize_warned = false


## A press with an accepted tool. A covered screw does nothing. A
## stripped or seized screw grinds instead of turning, and the tool
## stays in the hand.
func engage(tool: Tool) -> void:
	if is_covered():
		return
	if is_stripped():
		_press_stripped(tool)
	elif is_seized:
		_press_seized(tool)
	else:
		super.engage(tool)
		_start_microgame()


## Its layer is back on. A screw in its hole sits loose, turned back and
## slid out, ready to be driven in. A screw on the bench gets the
## outline until a press brings it back (`come_back()`).
func set_install_mode() -> void:
	super.set_install_mode()
	is_install_mode = true
	if travel == Travel.HOME:
		head.rotation = _home_head_rotation - LOOSE_TURN_RAD
		_snap_slide(1.0)
	elif travel == Travel.RESTING:
		_start_outline()
		# Its return is due: a screw already resting within
		# its seat's reach goes back by itself instead of
		# waiting for a press. Deferred, so the subclass
		# overrides of this mode change run first.
		call_deferred("_seat_if_resting_on_hole")


## The screw's return is due and it already rests within a
## seat's reach (dropped there, or slid there coming out):
## it flies in loose, ready to be driven home.
func _seat_if_resting_on_hole() -> void:
	if not can_come_back() or is_returning or is_carried:
		return
	var target := find_seat_target(_get_rest_middle())
	if is_instance_valid(target):
		come_back(target)


## Where a resting screw's middle sits, in world pixels:
## where a press on it lands.
func _get_rest_middle() -> Vector2:
	return bench_art.global_position + rest_hit_offset
	if is_stripped():
		# Stand-in until LX19. A pried screw is scrap, and a new one comes
		# from the parts bin. Until then the old one comes back as new.
		health = max_health
		_is_strip_warned = false
		_update_head_frame()


## Takes the screw out: a pop, the driver goes back to the hand, and the
## screw pulls itself out of its hole and slides off to its rest spot. It
## stays ACTIVE until it is out of the hole, so its layer waits for it, and
## then finish() tells the layer and the item.
func remove() -> void:
	G.audio.play_sound(&"lid_pop")
	slide = 1.0
	release_tool()
	removed.emit()
	travel = Travel.PULLING_OUT
	animation_player.play(pull_out_animation)
	animation_player.advance(0.0)


## Drives the screw home after its layer was put back. The microgame turns
## the head home before it calls this, and the screw ends up all the way
## in.
func install() -> void:
	G.audio.play_sound(&"click")
	slide = 0.0
	finish()
	installed.emit()


## How far the resting screw reaches from the middle the
## player grabs it by, in world pixels. The level keeps this
## much of the screw inside the workable area when it comes
## to rest, and it sets how much the screw bounces and skids
## when it lands there.
func get_rest_radius_px() -> float:
	return rest_hit_radius_px


## The level starts bringing this resting screw back to the
## workable area. Its set-down roll and its pick-up turn stop
## where they are, and it cannot be picked up again until it
## comes to rest.
func start_bench_return() -> void:
	is_returning = true
	_stop_roll()
	_stop_rest_pulse()
	if is_instance_valid(_pickup_tween):
		_pickup_tween.kill()
	if is_instance_valid(_travel_tween):
		_travel_tween.kill()


## The screw has come to rest inside the workable area. The
## turn it landed at is the turn it rests at.
## The sound of the screw hitting the bench, played by the
## level at its first bounce, not when it comes to rest.
func play_landing_sound() -> void:
	G.audio.play_sound(&"screw_drop")


func finish_bench_return() -> void:
	is_returning = false
	_rest_rotation = bench_art.rotation


## True when a press on this resting screw would bring it back: its layer
## is back on and it waits at its rest spot.
func can_come_back() -> bool:
	return is_install_mode and travel == Travel.RESTING


## True when this screw and `other` are screws of a given type, so
## either one fits the other's hole. A flathead screw and a
## Phillips screw are different types and never trade holes.
func is_interchangeable_with(other: Screw) -> bool:
	return (
		is_instance_valid(other)
		and other != self
		and type == other.type
	)


## The hole this resting screw seats into when dropped at a
## world position, or null when no hole is close enough. Its own
## hole counts, and so does every other empty hole of its type on
## its layer: a hole whose screw still rests on the bench, waiting
## to come back. The closest such hole wins.
func find_seat_target(global_point: Vector2) -> Screw:
	if not can_come_back():
		return null
	var layer := get_layer()
	if not is_instance_valid(layer):
		return null
	var best: Screw = null
	var best_distance := G.settings.screw_seat_snap_px
	for point in layer.get_points():
		var hole := point as Screw
		if not is_instance_valid(hole):
			continue
		if hole != self:
			if not is_interchangeable_with(hole):
				continue
			if not hole.can_come_back():
				continue
		var distance := global_point.distance_to(
			hole.global_position
		)
		if distance <= best_distance:
			best_distance = distance
			best = hole
	return best


## True while the resting screw shows the outline that says a press
## brings it back.
func is_showing_outline() -> bool:
	return is_instance_valid(_outlined_bench_art)


## True when a world position is on this screw while it rests on the
## bench.
func has_rest_point(global_point: Vector2) -> bool:
	if travel != Travel.RESTING:
		return false
	var middle := _get_rest_middle()
	return (
		middle.distance_squared_to(global_point)
		<= rest_hit_radius_px * rest_hit_radius_px
	)


## The player picked this resting screw up to drag it. It turns a
## little in the fingers: a random delta within 45 degrees either
## way from how it lies.
func on_picked_up() -> void:
	_stop_roll()
	if is_instance_valid(_pickup_tween):
		_pickup_tween.kill()
	var target_rotation := (
		bench_art.rotation
		+ randf_range(-_PICKUP_MAX_TURN_RAD, _PICKUP_MAX_TURN_RAD)
	)
	_rest_rotation = target_rotation
	_pickup_tween = create_tween()
	_pickup_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pickup_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_pickup_tween.tween_property(
		bench_art,
		"rotation",
		target_rotation,
		_PICKUP_TURN_SEC,
	)


## Sends the resting screw back over its hole, where it sinks in, loose
## and ready to be driven in. With a `target` screw of the same
## type, it sinks into that screw's hole instead, and the two
## screws trade holes: the target screw's hole is this one's now,
## and it waits on the bench for the hole this screw left behind.
func come_back(target: Screw = null) -> void:
	if not G.check(can_come_back()):
		return
	if is_instance_valid(target) and target != self:
		if not G.check(
			is_interchangeable_with(target)
			and target.can_come_back()
			and get_layer() == target.get_layer()
		):
			return
		_trade_holes_with(target)
	if is_instance_valid(G.level):
		G.level.free_screw_rest_spot(self)
	_stop_outline()
	_stop_rest_pulse()
	_stop_roll()
	if is_instance_valid(_pickup_tween):
		_pickup_tween.kill()
	travel = Travel.RETURNING
	_travel_from = bench_art.global_position
	_start_travel(_reach_hole, _bench_art_home_rotation)


## One short pulse that shows this point still needs work. A resting
## screw pulses on the bench.
func pulse() -> void:
	if travel == Travel.HOME:
		super.pulse()
		return
	if travel != Travel.RESTING:
		return
	_stop_rest_pulse()
	_rest_pulse_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	_rest_pulse_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var half_sec := G.settings.point_pulse_sec * 0.5
	_rest_pulse_tween.tween_property(
		bench_art,
		"scale",
		_bench_art_home_scale * _PULSE_SCALE,
		half_sec,
	)
	_rest_pulse_tween.tween_property(
		bench_art,
		"scale",
		_bench_art_home_scale,
		half_sec,
	)


## Shows or hides the idle hint. A resting screw highlights its
## bench art, where the player's press lands. A screw in its hole
## highlights at the hole like any other point. Clearing the hint
## never clears the install outline of a screw that can come back,
## which the game shows on its own.
func set_hint_active(is_active: bool) -> void:
	if travel == Travel.RESTING:
		_is_rest_hint_active = is_active
		if is_active:
			_start_outline()
		elif not can_come_back():
			_stop_outline()
		return
	super.set_hint_active(is_active)


## True while the idle hint shows, or the resting screw already
## shows its own return outline.
func is_hint_active() -> bool:
	if travel == Travel.RESTING:
		return is_showing_outline()
	return super.is_hint_active()


## Starts the microgame once the tool is IN_USE. Each screw type
## overrides it.
func _start_microgame() -> void:
	pass


## The driver no longer bites: a press grinds and nopes. Only the pliers
## work now (LX19).
func _press_stripped(tool: Tool) -> void:
	G.audio.play_sound(&"grind")
	if not _is_strip_warned:
		_is_strip_warned = true
		tool.nope()
		return
	# Stand-in until LX19. Without the pliers a stripped screw would block
	# the item, so the press after the warning pries it out.
	mode = Mode.ACTIVE
	if is_instance_valid(_pry_tween):
		_pry_tween.kill()
	_pry_tween = create_tween()
	_pry_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_pry_tween.tween_interval(_PRY_DELAY_SEC)
	_pry_tween.tween_callback(_pry)


# Stand-in until LX19.
func _pry() -> void:
	if is_install_mode:
		# It can't come out with its layer on, so it goes in.
		head.rotation = _home_head_rotation
		install()
	else:
		remove()


## A seized screw won't turn. The first try only grinds as a warning, and
## each stalled try after it costs 1 damage.
func _press_seized(tool: Tool) -> void:
	G.audio.play_sound(&"grind")
	tool.nope()
	if not _is_seize_warned:
		_is_seize_warned = true
		return
	take_damage(1)


func _add_defect(defect: RepairQuality.Defect) -> void:
	var item := get_item()
	if is_instance_valid(item):
		item.quality.add_defect(defect, global_position, self)


func _update_head_frame() -> void:
	var frame := get_head_frame()
	if head is AnimatedSprite2D:
		(head as AnimatedSprite2D).frame = frame
	else:
		# Placeholder until LX24.
		head.modulate = _PLACEHOLDER_FRAME_TINTS[frame]


func _update_rust() -> void:
	# Placeholder until LX24.
	if is_instance_valid(rust_overlay):
		rust_overlay.visible = is_seized
	if is_instance_valid(rust_streak):
		rust_streak.visible = is_seized


## Moves the art and the hit shape to where `slide` says. Home is exact
## at 0.
func _update_slide_position() -> void:
	if not is_node_ready():
		return
	slide_node.position = _home_slide_position + _slide_offset * slide
	hit_shape.position = _home_shape_position + _shape_slide_offset * slide


## Sets `slide` with no easing from where the screw was, like a screw that
## has just reappeared.
func _snap_slide(fraction: float) -> void:
	slide = fraction
	reset_physics_interpolation()


## The first key of `pull_out_animation` for `slide_node`'s position: the
## backed-out pose.
func _get_backed_out_position() -> Vector2:
	var animation := animation_player.get_animation(pull_out_animation)
	var animation_root := animation_player.get_node(animation_player.root_node)
	var track := animation.find_track(
		NodePath("%s:position" % animation_root.get_path_to(slide_node)),
		Animation.TYPE_VALUE,
	)
	if not G.ensure(
		track >= 0 and animation.track_get_key_count(track) > 0,
		"%s has no position key for %s" % [pull_out_animation, slide_node],
	):
		return slide_node.position
	return animation.track_get_key_value(track, 0)


## Where the bench art goes while the screw is out of its hole: next to
## the item, so it stays on the bench when the layer lifts off, and draws
## above the item and below the tools.
func _get_bench_parent() -> Node:
	var item := get_item()
	if is_instance_valid(item) and is_instance_valid(item.get_parent()):
		return item.get_parent()
	return get_parent()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != pull_out_animation:
		return
	if travel == Travel.PULLING_OUT:
		_leave_hole()
	elif travel == Travel.SINKING:
		_settle_in_hole()


## Out of the hole: the unclipped art takes over from the clipped one
## and the screw comes to rest right where the pull-out left it. It
## does not slide off by itself. The player drags it wherever they
## want it on the bench (docs/design/screw_pullout.md). Only now do
## the layer and the item hear that the screw is out.
func _leave_hole() -> void:
	clip_space.hide()
	hit_shape.set_deferred("disabled", true)
	bench_art.show()
	bench_art.reparent(_get_bench_parent())
	bench_art.rotation = _bench_art_home_rotation
	bench_art.scale = _bench_art_home_scale
	bench_art.z_index = 10
	bench_art.reset_physics_interpolation()
	_rest_rotation = bench_art.rotation
	travel = Travel.RESTING
	G.audio.play_sound(&"screw_drop")
	if is_instance_valid(G.level):
		G.level.register_resting_screw(self)
	if is_install_mode:
		_start_outline()
	finish()


func _reach_rest_spot() -> void:
	travel = Travel.RESTING
	G.audio.play_sound(&"screw_drop")
	if is_install_mode:
		_start_outline()


## The screw was just set down on the table after a drag. A
## screw is a squat cone (head about 24 px across, shaft about
## 11), so lying on its side it rolls like one: around the
## cone's apex, which sits past the pointy end at the distance
## the two radii set. The apex stays put while the body travels
## sideways and yaws around it, the wide head sweeping the
## longest arc. The yaw is sized from a head sweep at whatever
## angle the screw starts from, and a fast release rolls it
## toward the drag's motion. It does not roll when the unscrew
## microgame finishes: only a set-down after being carried
## counts.
func on_set_down(release_velocity := Vector2.ZERO) -> void:
	G.audio.play_sound(&"screw_drop")
	_roll_from_position = bench_art.global_position
	_roll_from_rotation = bench_art.rotation
	var head_start := bench_art.to_global(_HEAD_LOCAL)
	var tip_start := bench_art.to_global(_TIP_LOCAL)
	var axis := tip_start - head_start
	var length := maxf(axis.length(), 1.0)
	var head_radius := bench_art.to_global(
		_HEAD_LOCAL + Vector2(_HEAD_RADIUS_LOCAL, 0.0),
	).distance_to(head_start)
	var shaft_radius := bench_art.to_global(
		_TIP_LOCAL + Vector2(_SHAFT_RADIUS_LOCAL, 0.0),
	).distance_to(tip_start)
	# Where the cone's apex sits past the tip: from there, the
	# radii grow in proportion along the whole screw.
	var apex_distance := (
		length
		* shaft_radius
		/ maxf(head_radius - shaft_radius, 0.5)
	)
	_roll_apex = tip_start + axis.normalized() * apex_distance
	var direction := 1.0 if randf() < 0.5 else -1.0
	if release_velocity.length() > _ROLL_FLING_MIN_SPEED:
		# The head sweeps toward the drag's motion.
		var swing := Vector2(-axis.y, axis.x).normalized()
		if not is_zero_approx(swing.dot(release_velocity)):
			direction = signf(swing.dot(release_velocity))
	var head_sweep := randf_range(_ROLL_HEAD_MIN_PX, _ROLL_HEAD_MAX_PX)
	_roll_angle_rad = (
		direction * head_sweep / (apex_distance + length)
	)
	var duration_sec := clampf(
		_ROLL_SEC * sqrt(head_sweep / _ROLL_HEAD_MIN_PX),
		_ROLL_SEC,
		1.5,
	)
	_roll_tween = create_tween()
	_roll_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_roll_tween.tween_method(_apply_roll, 0.0, 1.0, duration_sec)


## Stops a set-down roll where it is.
func _stop_roll() -> void:
	if is_instance_valid(_roll_tween):
		_roll_tween.kill()


## Puts the rolling screw `weight` of the way through its roll:
## the body turns about the cone's fixed apex, eased out.
func _apply_roll(weight: float) -> void:
	var eased := 1.0 - pow(1.0 - weight, 3.0)
	bench_art.global_position = (
		_roll_apex
		+ (_roll_from_position - _roll_apex).rotated(
			_roll_angle_rad * eased,
		)
	)
	bench_art.rotation = _roll_from_rotation + _roll_angle_rad * eased
	_rest_rotation = bench_art.rotation


## Trades holes with `other`, a screw of the same type on the
## same layer: this screw's root takes the other screw's place on
## the layer, and the other screw's root takes this one's. Each
## physical screw keeps its own health, head and tuning. A screw
## resting on the bench keeps its bench art where it lies: only
## the roots, which stay at the holes, trade places.
func _trade_holes_with(other: Screw) -> void:
	var own_position := position
	position = other.position
	other.position = own_position
	reset_physics_interpolation()
	other.reset_physics_interpolation()


## Over the hole: the clipped art takes over again and sinks into the
## hole, turned back like a loose screw.
func _reach_hole() -> void:
	G.audio.play_sound(&"screw_seated")
	bench_art.reparent(self, false)
	bench_art.position = _bench_art_home_position
	bench_art.rotation = _bench_art_home_rotation
	bench_art.scale = _bench_art_home_scale
	bench_art.z_index = 0
	bench_art.hide()
	head.rotation = _home_head_rotation - LOOSE_TURN_RAD
	clip_space.show()
	reset_physics_interpolation()
	travel = Travel.SINKING
	animation_player.play_backwards(pull_out_animation)
	animation_player.advance(0.0)


## Sunk in: the screw sits loose in its hole, raised and turned back, and
## can be driven in.
func _settle_in_hole() -> void:
	travel = Travel.HOME
	_snap_slide(1.0)
	hit_shape.set_deferred("disabled", false)


## Slides the bench art from `_travel_from`, turning it to
## `to_rotation` on the way, eased, then calls `on_done`.
func _start_travel(on_done: Callable, to_rotation: float) -> void:
	if is_instance_valid(_travel_tween):
		_travel_tween.kill()
	_travel_tween = create_tween().set_parallel()
	_travel_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_travel_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var duration_sec := G.settings.screw_travel_sec
	_travel_tween.tween_method(
		_place_bench_art,
		0.0,
		1.0,
		duration_sec,
	)
	_travel_tween.tween_property(
		bench_art,
		"rotation",
		to_rotation,
		duration_sec,
	)
	_travel_tween.chain().tween_callback(on_done)


## Puts the bench art `weight` of the way along its trip. A trip back
## ends over the hole, even if the screw moved since it began, and
## arcs up and over it so the screw always comes down into its hole
## from above, never sliding in sideways.
func _place_bench_art(weight: float) -> void:
	var to_position := _travel_to
	if travel == Travel.RETURNING:
		to_position = to_global(_bench_art_home_position)
		var arc := Vector2.UP * G.settings.screw_seat_arc_px
		bench_art.global_position = _travel_from.bezier_interpolate(
			_travel_from + arc,
			to_position + arc,
			to_position,
			weight,
		)
		return
	bench_art.global_position = _travel_from.lerp(to_position, weight)


## The outline on the resting screw: a press brings it back.
func _start_outline() -> void:
	if is_showing_outline():
		return
	if not bench_art is Sprite2D:
		return
	if not is_instance_valid(G.settings.outline_hint_material):
		return
	_outlined_bench_art = bench_art as Sprite2D
	_bench_material_before_outline = OutlineHint.apply_to_sprite(
		_outlined_bench_art,
	)


func _stop_outline() -> void:
	if is_instance_valid(_outlined_bench_art):
		OutlineHint.remove_from_sprite(
			_outlined_bench_art,
			_bench_material_before_outline,
		)
	_outlined_bench_art = null
	_bench_material_before_outline = null


func _stop_rest_pulse() -> void:
	if is_instance_valid(_rest_pulse_tween):
		_rest_pulse_tween.kill()
	bench_art.scale = _bench_art_home_scale
