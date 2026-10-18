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
## Once it is all the way out, it pulls itself out of the hole and slides
## off to a rest spot on the bench. When its layer is back on, a press
## sends it back to sink into its hole, loose and ready to be driven in
## (docs/design/screw_pullout.md). The root stays at the hole with the
## hole art and the clip mask. Only the art and the hit shape move.
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
var _outlined_bench_art: Sprite2D
var _bench_material_before_outline: Material


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
	health = max_health
	_update_head_frame()
	_update_rust()


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# The bench art is not a child while the screw is out of its hole.
	if is_instance_valid(bench_art) and bench_art.get_parent() != self:
		bench_art.queue_free()


## A screw out of its hole can't be engaged.
func can_engage() -> bool:
	return travel == Travel.HOME and super.can_engage()


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


## A press with an accepted tool. A stripped or seized screw grinds
## instead of turning, and the tool stays in the hand.
func engage(tool: Tool) -> void:
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
	G.audio.play_sound(&"pop")
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


## True when a press on this resting screw would bring it back: its layer
## is back on and it waits at its rest spot.
func can_come_back() -> bool:
	return is_install_mode and travel == Travel.RESTING


## True while the resting screw shows the outline that says a press
## brings it back.
func is_showing_outline() -> bool:
	return is_instance_valid(_outlined_bench_art)


## True when a world position is on this screw while it rests on the
## bench.
func has_rest_point(global_point: Vector2) -> bool:
	if travel != Travel.RESTING:
		return false
	var middle := bench_art.global_position + rest_hit_offset
	return (
		middle.distance_squared_to(global_point)
		<= rest_hit_radius_px * rest_hit_radius_px
	)


## Sends the resting screw back over its hole, where it sinks in, loose
## and ready to be driven in.
func come_back() -> void:
	if not G.check(can_come_back()):
		return
	if is_instance_valid(G.level):
		G.level.free_screw_rest_spot(self)
	_stop_outline()
	_stop_rest_pulse()
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


## Out of the hole: the unclipped art takes over from the clipped one and
## slides off to the screw's rest spot. Only now do the layer and the item
## hear that the screw is out.
func _leave_hole() -> void:
	travel = Travel.LEAVING
	clip_space.hide()
	hit_shape.set_deferred("disabled", true)
	bench_art.show()
	bench_art.reparent(_get_bench_parent())
	bench_art.rotation = _bench_art_home_rotation
	bench_art.scale = _bench_art_home_scale
	bench_art.reset_physics_interpolation()
	_rest_rotation = randf_range(0.0, TAU)
	_travel_from = bench_art.global_position
	_travel_to = _travel_from
	if is_instance_valid(G.level):
		_travel_to = G.level.take_screw_rest_spot(self)
	_start_travel(_reach_rest_spot, _rest_rotation)
	finish()


func _reach_rest_spot() -> void:
	travel = Travel.RESTING
	if is_install_mode:
		_start_outline()


## Over the hole: the clipped art takes over again and sinks into the
## hole, turned back like a loose screw.
func _reach_hole() -> void:
	bench_art.reparent(self, false)
	bench_art.position = _bench_art_home_position
	bench_art.rotation = _bench_art_home_rotation
	bench_art.scale = _bench_art_home_scale
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


## Puts the bench art `weight` of the way along its trip. A trip back ends
## over the hole, even if the screw moved since it began.
func _place_bench_art(weight: float) -> void:
	var to_position := _travel_to
	if travel == Travel.RETURNING:
		to_position = to_global(_bench_art_home_position)
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
