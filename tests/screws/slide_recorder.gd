extends RefCounted
## Records a screw's slide while a probe drives the screw, then checks the
## record (docs/design/screws.md "Removal"). Call `begin()` before the
## drive, `sample()` once per physics frame while the screw twists, and
## `check()` once it is done. The record ends where the screw stood when
## it emitted `removed` or `installed`, before a pull-out moves its art
## (docs/design/screw_pullout.md). The screws probe loads it by path, so
## it has no `class_name`.


## A screw must slide at least this many world pixels for a check on it to
## mean anything, so a screw that never slides fails the checks.
const MIN_SLIDE_PX := 1.0
## Positions and slides agree within this many pixels, and a position that
## must be exact within the second one.
const TOLERANCE_PX := 0.01
const EXACT_PX := 0.001
## A screw held still moves less than this between two frames.
const HOLD_TOLERANCE_PX := 0.0001

var _screw: FlatHeadScrew
var _tool: FlatHeadScrewDriver
## Where the screw's head sits when it is all the way in, in world pixels.
var _home := Vector2.ZERO
## Where the head stood and the slide when the screw emitted `removed` or
## `installed`, or `Vector2.INF` and -1 before that.
var _end_position := Vector2.INF
var _end_slide := -1.0
## One sample per frame: how far up the screen the screw is, and the phase
## of its cycle.
var _rises: Array[float] = []
var _phases: Array[int] = []
## The largest gaps between what the slide promises and what the nodes do.
var _sideways_px := 0.0
var _turn_gap := 0.0
var _follow_gap_px := 0.0
var _part_shift_px := 0.0
var _tip_gap_px := 0.0
## Where each part sat from the head in the first sample.
var _part_offsets: Array[Vector2] = []


## How far up the screen a screw's head sits from its home, in world
## pixels. The screw's node stays at its hole while the art slides.
static func get_rise(screw: FlatHeadScrew, home: Vector2) -> float:
	return home.y - screw.head.global_position.y


## Starts a new record for `screw`, whose home is `home`, driven by `tool`.
func begin(
	screw: FlatHeadScrew,
	tool: FlatHeadScrewDriver,
	home: Vector2,
) -> void:
	if is_instance_valid(_screw):
		for done: Signal in [_screw.removed, _screw.installed]:
			if done.is_connected(_on_screw_done):
				done.disconnect(_on_screw_done)
	_screw = screw
	_screw.removed.connect(_on_screw_done)
	_screw.installed.connect(_on_screw_done)
	_end_position = Vector2.INF
	_end_slide = -1.0
	_tool = tool
	_home = home
	_rises.clear()
	_phases.clear()
	_sideways_px = 0.0
	_turn_gap = 0.0
	_follow_gap_px = 0.0
	_part_shift_px = 0.0
	_tip_gap_px = 0.0
	_part_offsets.clear()


## Samples one frame: how far up the screw is and its cycle's phase, and the
## gaps between what the slide promises and what the nodes do.
func sample() -> void:
	var px := _screw.get_slide_height_px()
	var rise := get_rise(_screw, _home)
	var head_position := _screw.head.global_position
	_rises.append(rise)
	_phases.append(_screw._phase)
	_sideways_px = maxf(_sideways_px, absf(head_position.x - _home.x))
	# The slide follows the head's turn: a full turn out, or the loose turn
	# in install mode.
	var full_turn := Screw.LOOSE_TURN_RAD if _screw.is_install_mode else TAU
	var turned := absf(_screw.head.rotation - _screw._home_head_rotation)
	_turn_gap = maxf(_turn_gap, absf(_screw.slide - turned / full_turn))
	_follow_gap_px = maxf(_follow_gap_px, absf(rise - px * _screw.slide))
	var parts := _get_parts()
	for index in parts.size():
		var offset := parts[index].global_position - head_position
		if _part_offsets.size() < parts.size():
			_part_offsets.append(offset)
		else:
			_part_shift_px = maxf(
				_part_shift_px,
				offset.distance_to(_part_offsets[index]),
			)
	_tip_gap_px = maxf(
		_tip_gap_px,
		_tool.get_tip_position().distance_to(_screw.get_tip_position()),
	)


## Checks the record. `expect` is the probe's `_expect`, and `start_slide` is
## where the drive began: 0 for a fresh removal, the kept slide after an
## unseat, and 1 for an install.
func check(expect: Callable, label: String, start_slide: float) -> void:
	var count := _rises.size()
	if not expect.call(
		count > 2,
		"%s: the slide was sampled (%d frames)" % [label, count],
	):
		return
	var px := _screw.get_slide_height_px()
	var is_install := _screw.is_install_mode
	var direction := -1.0 if is_install else 1.0
	var end_slide := 0.0 if is_install else 1.0
	var first_rise := _rises[0]
	var last_rise := _rises[count - 1]
	var reversals := 0
	var held_frames := 0
	var largest_hold_px := 0.0
	for index in count - 1:
		var rise_step := _rises[index + 1] - _rises[index]
		if rise_step * direction < -HOLD_TOLERANCE_PX:
			reversals += 1
		if _phases[index] != FlatHeadScrew.Phase.PAUSE:
			continue
		largest_hold_px = maxf(largest_hold_px, absf(rise_step))
		# Count only the pauses part way along, not at home or all the way
		# out, where a screw that never slides would also sit still.
		var rise := _rises[index]
		if absf(rise) > 0.1 * px and absf(rise - px) > 0.1 * px:
			held_frames += 1
	expect.call(
		absf(first_rise - px * start_slide) < TOLERANCE_PX
		and absf(last_rise - px * end_slide) < px * 0.01 + TOLERANCE_PX
		and absf(last_rise - first_rise) > MIN_SLIDE_PX
		and reversals == 0,
		"%s: slides from %.2f to %.2f px up, one way, fully by the end of its"
		% [label, first_rise, last_rise]
		+ " last twist (%d reversals, of %.1f px)" % [reversals, px],
	)
	var min_held_frames := roundi(
		0.5
		* G.settings.flathead_pause_sec
		* Engine.physics_ticks_per_second
	)
	expect.call(
		held_frames >= min_held_frames and largest_hold_px < HOLD_TOLERANCE_PX,
		"%s: holds still in the pauses between twists (%d pause frames part"
		% [label, held_frames]
		+ " way along, largest move %.5f px)" % largest_hold_px,
	)
	expect.call(
		_turn_gap < 0.0005 and _follow_gap_px < TOLERANCE_PX,
		"%s: eased like the head's turn (slide vs turn gap %.5f, position vs"
		% [label, _turn_gap]
		+ " slide gap %.5f px)" % _follow_gap_px,
	)
	expect.call(
		_sideways_px < TOLERANCE_PX,
		"%s: straight up the screen, not along its own axis (sideways %.5f"
		% [label, _sideways_px]
		+ " px, slot turned %.0f deg in its scene)"
		% rad_to_deg(_screw._home_head_rotation),
	)
	expect.call(
		_part_shift_px < TOLERANCE_PX and _tip_gap_px < TOLERANCE_PX,
		"%s: head, rust, side view and hit shape move as one, and the driver's"
		% label
		+ " tip follows the slot (parts shifted %.5f px, tip gap %.5f px)"
		% [_part_shift_px, _tip_gap_px],
	)
	var end_position := _home + Vector2.UP * px * end_slide
	var end_gap_px := _end_position.distance_to(end_position)
	expect.call(
		_end_slide == end_slide and end_gap_px < EXACT_PX,
		"%s: ends %s (slide %.3f, %.5f px off)"
		% [
			label,
			"exactly home" if is_install else "all the way out",
			_end_slide,
			end_gap_px,
		],
	)


## Keeps where the screw stood as it finished: the end of the record.
func _on_screw_done() -> void:
	_end_position = _screw.head.global_position
	_end_slide = _screw.slide


## The parts of a screw that must slide with its head: the rust on the
## head, the side view and the hit shape.
func _get_parts() -> Array[Node2D]:
	var parts: Array[Node2D] = [_screw.rust_overlay as Node2D]
	parts.append(_screw.slide_node.get_node("AnglePerspective") as Node2D)
	parts.append(_screw.hit_shape)
	return parts
