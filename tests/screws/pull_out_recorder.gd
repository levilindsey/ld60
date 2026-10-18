extends RefCounted
## Records a screw's trip out of its hole to its rest spot on the bench and
## back, and checks each step (docs/design/screw_pullout.md). Call
## `watch()` before the step starts: it then samples the screw once per
## physics frame by itself, until `stop()`. Each check reads the samples
## since `watch()`. The screws probe loads it by path, so it has no
## `class_name`.


## Positions that must be exact agree within this many world pixels.
const EXACT_PX := 0.001
## The bench art takes over from the clipped side view within this many
## world pixels, and within this fraction of its scale and this many
## radians of its turn, so the swap does not pop.
const SWAP_TOLERANCE_PX := 0.5
const SWAP_SCALE_TOLERANCE := 0.01
## A step may run this many frames longer or shorter than its length.
const FRAME_SLACK := 2

var _screw: FlatHeadScrew
var _tree: SceneTree
## One sample per physics frame since `watch()`, oldest first.
var _samples: Array[Dictionary] = []


## Starts a new record of `screw`.
func watch(screw: FlatHeadScrew) -> void:
	stop()
	_screw = screw
	_tree = screw.get_tree()
	_samples.clear()
	_tree.physics_frame.connect(_sample)


## Stops sampling. The record stays for the checks.
func stop() -> void:
	if is_instance_valid(_tree) and _tree.physics_frame.is_connected(_sample):
		_tree.physics_frame.disconnect(_sample)


## Checks a pull-out, watched from before the last twist until the screw
## rests: the clipped side view rises out of the hole while the layer
## waits, the bench art takes over at the end without a pop, and it slides
## to rest spot `rest_spot` (`Level.get_screw_rest_position()`).
func check_pull_out(
	expect: Callable,
	label: String,
	rest_spot: int,
) -> void:
	var rest_position := G.level.get_screw_rest_position(rest_spot)
	var start := _find(Screw.Travel.PULLING_OUT)
	if not expect.call(
		start > 0 and _samples[start - 1].travel == Screw.Travel.HOME,
		"%s: the pull-out starts at the hole (sample %d of %d)"
		% [label, start, _samples.size()],
	):
		return
	var first := _samples[start]
	expect.call(
		first.speed > 0.0
		and first.clip_visible
		and not first.bench_visible
		and first.mode == InteractionPoint.Mode.ACTIVE,
		"%s: the pull-out plays forward right after the last twist, clipped"
		% label
		+ " by the hole (speed %.1f, clip %s, bench art %s)"
		% [first.speed, first.clip_visible, first.bench_visible],
	)
	var swap := _find(Screw.Travel.LEAVING, start)
	if not expect.call(swap > start, "%s: the screw leaves its hole" % label):
		return
	var pull_frames := swap - start
	var is_clipped := true
	var is_rising := true
	var is_layer_waiting := true
	for index in range(start, swap):
		var sample := _samples[index]
		is_clipped = (
			is_clipped
			and sample.travel == Screw.Travel.PULLING_OUT
			and sample.clip_visible
			and not sample.bench_visible
		)
		is_layer_waiting = (
			is_layer_waiting
			and sample.mode == InteractionPoint.Mode.ACTIVE
			and not sample.layer_moving
		)
		if index > start:
			is_rising = (
				is_rising
				and sample.side_position.y < _samples[index - 1].side_position.y
			)
	var length_frames := _get_animation_frames()
	expect.call(
		absi(pull_frames - length_frames) <= FRAME_SLACK
		and is_clipped
		and is_rising,
		"%s: the side view rises out of the hole, clipped, for the whole"
		% label
		+ " pull-out (%d frames of %d)" % [pull_frames, length_frames],
	)
	expect.call(
		is_layer_waiting,
		"%s: the screw and its layer wait for the pull-out (still ACTIVE, the"
		% label
		+ " layer not moving)",
	)
	var before := _samples[swap - 1]
	var after := _samples[swap]
	expect.call(
		not after.clip_visible
		and after.bench_visible
		and not after.bench_on_screw
		and after.shape_disabled
		and after.mode == InteractionPoint.Mode.FINISHED,
		"%s: at the end of the pull-out the bench art takes over, the hit"
		% label
		+ " shape turns off and the screw finishes",
	)
	# The side view holds its end pose once the animation is done, and the
	# hidden bench art sat at its home spot under the screw just before. By
	# the swap frame the bench art may have begun its eased slide, so its
	# position is compared from the frame before, and its scale and turn
	# from the swap frame, where it shows.
	var gap_px: float = after.side_position.distance_to(before.bench_position)
	var scale_ratio: float = after.bench_scale.x / after.side_scale.x
	var turn_gap: float = absf(
		angle_difference(after.bench_rotation, after.side_rotation)
	)
	expect.call(
		gap_px < SWAP_TOLERANCE_PX
		and absf(scale_ratio - 1.0) < SWAP_SCALE_TOLERANCE
		and turn_gap < SWAP_SCALE_TOLERANCE,
		"%s: no pop at the swap: the bench art starts where the side view"
		% label
		+ " ends (%.3f px apart, scale ratio %.4f, turned %.4f rad)"
		% [gap_px, scale_ratio, turn_gap],
	)
	var rest := _find(Screw.Travel.RESTING, swap)
	if not expect.call(rest > swap, "%s: reaches its rest spot" % label):
		return
	var travel_frames := rest - swap
	var expected_frames := _get_travel_frames()
	var rest_gap_px: float = _samples[rest].bench_position.distance_to(
		rest_position
	)
	expect.call(
		absi(travel_frames - expected_frames) <= FRAME_SLACK
		and rest_gap_px < EXACT_PX
		and _samples[rest].bench_visible,
		"%s: the bench art slides to its rest spot in %d frames (of %d), %.5f"
		% [label, travel_frames, expected_frames, rest_gap_px]
		+ " px off",
	)


## Checks that the screw stayed at rest spot `rest_spot` in every sample
## since it began to rest, while its layer lifted off and settled, and did
## not glow, since it cannot come back yet.
func check_rest_kept(
	expect: Callable,
	label: String,
	rest_spot: int,
) -> void:
	var rest_position := G.level.get_screw_rest_position(rest_spot)
	var rest := _find(Screw.Travel.RESTING)
	if not expect.call(
		rest >= 0,
		"%s: the screw rests (%d frames watched)" % [label, _samples.size()],
	):
		return
	var largest_gap_px := 0.0
	var is_resting := true
	var moving_frames := 0
	for index in range(rest, _samples.size()):
		var sample := _samples[index]
		is_resting = (
			is_resting
			and sample.travel == Screw.Travel.RESTING
			and not sample.glowing
		)
		largest_gap_px = maxf(
			largest_gap_px,
			sample.bench_position.distance_to(rest_position),
		)
		if sample.layer_moving:
			moving_frames += 1
	var last := _samples[_samples.size() - 1]
	expect.call(
		is_resting
		and largest_gap_px < EXACT_PX
		and moving_frames > 0
		and not last.layer_on
		and not last.layer_moving,
		"%s: stays at its rest spot, unlit, while its layer lifts off (%d"
		% [label, _samples.size() - rest]
		+ " frames"
		+ " resting, %d with the layer moving, %.5f px off)"
		% [moving_frames, largest_gap_px],
	)


## Checks that a press, made after `watch()`, left the resting screw where
## it was.
func check_press_ignored(
	expect: Callable,
	label: String,
	rest_spot: int,
) -> void:
	var rest_position := G.level.get_screw_rest_position(rest_spot)
	var largest_gap_px := 0.0
	var is_resting := not _samples.is_empty()
	for sample in _samples:
		is_resting = is_resting and sample.travel == Screw.Travel.RESTING
		largest_gap_px = maxf(
			largest_gap_px,
			sample.bench_position.distance_to(rest_position),
		)
	expect.call(
		is_resting and largest_gap_px < EXACT_PX and not _screw.can_come_back(),
		"%s: a press on the resting screw does nothing while its layer is off"
		% label
		+ " (%d frames, %.5f px off)" % [_samples.size(), largest_gap_px],
	)


## Checks a trip back, watched from before the press on the resting screw
## until it is home: the bench art slides back over the hole, the clipped
## side view takes over and sinks in, and the screw ends loose, raised and
## ready to be driven in.
func check_come_back(expect: Callable, label: String) -> void:
	var back := _find(Screw.Travel.RETURNING)
	var sink := _find(Screw.Travel.SINKING, maxi(back, 0))
	if not expect.call(
		back >= 0 and sink > back,
		"%s: a press brings the screw back (sample %d, over the hole at %d)"
		% [label, back, sink],
	):
		return
	var is_glow_stopped := true
	for index in range(back, _samples.size()):
		is_glow_stopped = is_glow_stopped and not _samples[index].glowing
	expect.call(
		back > 0 and _samples[back - 1].glowing and is_glow_stopped,
		"%s: the resting screw glows until the press, then stops" % label,
	)
	var expected_frames := _get_travel_frames()
	var before := _samples[sink - 1]
	var after := _samples[sink]
	expect.call(
		absi(sink - back - expected_frames) <= FRAME_SLACK
		and before.bench_visible
		and not before.clip_visible,
		"%s: the bench art slides back over the hole in %d frames (of %d)"
		% [label, sink - back, expected_frames],
	)
	expect.call(
		after.clip_visible
		and not after.bench_visible
		and after.bench_on_screw
		and after.speed < 0.0,
		"%s: over the hole the side view takes over and the pull-out plays"
		% label
		+ " backwards (speed %.1f)" % after.speed,
	)
	var home := _find(Screw.Travel.HOME, sink)
	if not expect.call(home > sink, "%s: the screw sinks back in" % label):
		return
	var is_clipped := true
	var is_sinking := true
	for index in range(sink, home):
		var sample := _samples[index]
		is_clipped = (
			is_clipped and sample.clip_visible and not sample.bench_visible
		)
		if index > sink:
			is_sinking = (
				is_sinking
				and sample.side_position.y > _samples[index - 1].side_position.y
			)
	var length_frames := _get_animation_frames()
	expect.call(
		absi(home - sink - length_frames) <= FRAME_SLACK
		and is_clipped
		and is_sinking,
		"%s: the side view sinks into the hole, clipped (%d frames of %d)"
		% [label, home - sink, length_frames],
	)
	var end := _samples[_samples.size() - 1]
	var backed_out_position := (
		_screw._home_slide_position + _screw._slide_offset
	)
	var head_gap := absf(
		_screw.head.rotation
		- (_screw._home_head_rotation - Screw.LOOSE_TURN_RAD)
	)
	expect.call(
		end.travel == Screw.Travel.HOME
		and end.slide == 1.0
		and end.clip_visible
		and not end.bench_visible
		and not end.shape_disabled
		and end.slide_position.distance_to(backed_out_position) < EXACT_PX
		and head_gap < 0.0001,
		"%s: ends at its hole with the clip shown, slide %.3f, the art backed"
		% [label, end.slide]
		+ " out and the head turned back like a loose screw",
	)


## The first sample from `from` on whose trip is at `travel`, or -1.
func _find(travel: Screw.Travel, from := 0) -> int:
	for index in range(from, _samples.size()):
		if _samples[index].travel == travel:
			return index
	return -1


## How many physics frames the pull-out animation lasts.
func _get_animation_frames() -> int:
	var animation := _screw.animation_player.get_animation(
		_screw.pull_out_animation
	)
	return roundi(animation.length * Engine.physics_ticks_per_second)


## How many physics frames a trip to or from the rest spot lasts.
func _get_travel_frames() -> int:
	return roundi(G.settings.screw_travel_sec * Engine.physics_ticks_per_second)


func _sample() -> void:
	if not is_instance_valid(_screw):
		stop()
		return
	var side_view := _screw.slide_node.get_node("AnglePerspective") as Node2D
	var layer := _screw.get_layer()
	_samples.append({
		"travel": _screw.travel,
		"mode": _screw.mode,
		"slide": _screw.slide,
		"slide_position": _screw.slide_node.position,
		"speed": (
			_screw.animation_player.get_playing_speed()
			if _screw.animation_player.is_playing()
			else 0.0
		),
		"clip_visible": _screw.clip_space.visible,
		"bench_visible": _screw.bench_art.visible,
		"bench_on_screw": _screw.bench_art.get_parent() == _screw,
		"bench_position": _screw.bench_art.global_position,
		"bench_scale": _screw.bench_art.global_scale,
		"bench_rotation": _screw.bench_art.global_rotation,
		"side_position": side_view.global_position,
		"side_scale": side_view.global_scale,
		"side_rotation": side_view.global_rotation,
		"shape_disabled": _screw.hit_shape.disabled,
		"glowing": (
			is_instance_valid(_screw._glow_tween)
			and _screw._glow_tween.is_valid()
		),
		"layer_moving": is_instance_valid(layer) and layer.is_moving,
		"layer_on": is_instance_valid(layer) and layer.is_on,
	})
