class_name FlatHeadScrew
extends Screw
## A flathead screw (docs/design/flathead.md). The driver turns it out by
## itself in slow twists, and each twist drifts the tip along the slot.
## The player moves the pointer along the slot to keep the tip seated. If
## the tip drifts off the end of the slot, it skids out and the screw takes
## 1 damage.


enum Phase {
	## Between twists. Nothing drifts, so the player can recenter.
	PAUSE,
	## The screw and the driver turn, and the tip drifts.
	TWIST,
}

## Length of the skid scratch, in world pixels.
const _SKID_SIZE_PX := 18.0
## How far the driver hops off the screw when the tip skids out.
const _UNSEAT_HOP_PX := 14.0
## Past this fraction of the seat tolerance, the tip scrapes and shakes.
const _DANGER_FRACTION := 0.7
## How far the tip shakes near the end of the slot.
const _DANGER_SHAKE_PX := 1.5

## How far the tip can move along the slot from the center before it skids
## out, about half the slot's length.
@export var seat_tolerance_px := 9.0
## The chance that a twist drifts the tip this screw's way. The other
## twists drift it the other way (flathead.md "Tuning").
@export_range(0.0, 1.0) var slip_bias := 0.9
## Twists that take the screw out.
@export var twists_needed := 4
## Twists that drive the screw back in after its layer was put back.
@export var install_twists := 2
## Sparks at the tip when it skids out.
@export var sparks: CPUParticles2D

## The tip's distance from the slot's center, along the slot.
var tip_offset_px := 0.0

## Twists finished toward taking the screw out, or driving it in. An unseat
## keeps them.
var _twists_done := 0
var _phase := Phase.PAUSE
## Seconds since the current phase started.
var _phase_sec := 0.0
## The head's angle when the current twist started, and where it ends.
var _twist_from_rotation := 0.0
var _twist_to_rotation := 0.0
## The screw's slide when the current twist started, and where it ends.
var _twist_from_slide := 0.0
var _twist_to_slide := 0.0
## The drift the current twist adds by its end, and how much of it the tip
## has taken so far.
var _twist_drift_px := 0.0
var _twist_drift_applied_px := 0.0
var _is_telegraphed := false
var _is_in_danger := false
## True once the first twist of an engage starts. From then on the driver
## turns with the head.
var _is_turning_tool := false
## The head's angle when the driver engaged. The driver turns by how far
## the head turned since.
var _engage_head_rotation := 0.0
## The way this screw's drifts mostly go along the slot: 1 or -1.
var _drift_sign := 1.0
## Drives the drifts only, so a seeded probe can repeat them.
var _random := RandomNumberGenerator.new()
## The pointer in viewport pixels at the last motion this screw handled.
var _last_pointer_screen_position := Vector2.ZERO


func _ready() -> void:
	super._ready()
	G.check(is_instance_valid(sparks))
	G.check(G.settings.flathead_slip_max < 1.0)
	G.check(G.settings.flathead_touch_gain >= 1.0)
	_random.randomize()
	_drift_sign = 1.0 if _random.randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	if mode == Mode.ACTIVE and is_instance_valid(engaged_tool):
		_advance_cycle(delta)
	# Places the engaged tool, if the cycle kept it.
	super(delta)


## Turns the driver with the head and puts its tip on the slot.
func place_engaged_tool() -> void:
	var driver := engaged_tool as FlatHeadScrewDriver
	if _is_turning_tool and is_instance_valid(driver):
		driver.set_twist_rotation(head.rotation - _engage_head_rotation)
	engaged_tool.place_tip(get_tip_position() + _get_danger_shake())


## Lets go of the driver and gives the pointer back to the hand.
func release_tool() -> void:
	if is_instance_valid(G.level):
		G.level.hand.clear_input_owner(self)
	_set_in_danger(false)
	super.release_tool()


func set_install_mode() -> void:
	super.set_install_mode()
	_twists_done = 0
	_reset_seat()


## The slot's direction in world space. It turns with the head.
func get_slot_axis() -> Vector2:
	return head.global_transform.y.normalized()


## Where the driver's tip sits: on the slot, `tip_offset_px` from its
## center.
func get_tip_position() -> Vector2:
	return head.global_position + get_slot_axis() * tip_offset_px


## The hand calls this on every pointer motion while this screw owns the
## pointer. Motion along the slot moves the tip. At rest the tip stops
## at the slot's ends, so a push can never skid it out. While the screw
## is turning the push may carry it past the end and skid it out.
## Motion across the slot does nothing. A touch drag is amplified by
## `flathead_touch_gain`, so a finger need not travel as far as the tip.
func on_pointer_moved(_global_position: Vector2) -> void:
	# Screen pixels, so a camera shake doesn't count as motion.
	var screen_delta := (
		G.level.hand.pointer_screen_position - _last_pointer_screen_position
	)
	_last_pointer_screen_position = G.level.hand.pointer_screen_position
	var world_delta := (
		G.level.hand.get_canvas_transform().affine_inverse().basis_xform(
			screen_delta
		)
	)
	var gain := 1.0
	if G.level.hand.is_touch:
		gain = G.settings.flathead_touch_gain
	var next_offset_px := (
		tip_offset_px + world_delta.dot(get_slot_axis()) * gain
	)
	if _phase == Phase.PAUSE:
		next_offset_px = clampf(
			next_offset_px,
			-seat_tolerance_px,
			seat_tolerance_px,
		)
	tip_offset_px = next_offset_px


## A finger can land anywhere, so motion counts from the new press.
func on_pointer_pressed(_global_position: Vector2) -> void:
	_last_pointer_screen_position = G.level.hand.pointer_screen_position


## One twist's drift along the slot (flathead.md "Drift"). It goes
## `direction_sign`'s way with probability `bias`, else the other way.
## Static, so a probe can check it against the `slip_bias` table.
static func pick_drift_px(
	random: RandomNumberGenerator,
	direction_sign: float,
	bias: float,
	tolerance_px: float,
	slip_min: float,
	slip_max: float,
) -> float:
	var drift_sign := (
		direction_sign if random.randf() < bias else -direction_sign
	)
	return (
		drift_sign
		* random.randf_range(slip_min, slip_max)
		* tolerance_px
	)


func _start_microgame() -> void:
	_reset_seat()
	_engage_head_rotation = head.rotation
	_last_pointer_screen_position = G.level.hand.pointer_screen_position
	G.level.hand.set_input_owner(self)


## One physics frame of the twist cycle: pause, telegraph, twist.
## The tip can only pass the slot's end while the screw is turning,
## pushed by the drift or by the player, so the unseat check runs only
## in that phase.
func _advance_cycle(delta: float) -> void:
	_phase_sec += delta
	if _phase == Phase.TWIST:
		_turn_and_drift()
		if absf(tip_offset_px) > seat_tolerance_px:
			_unseat()
			return
	_set_in_danger(
		absf(tip_offset_px) > seat_tolerance_px * _DANGER_FRACTION
	)
	match _phase:
		Phase.PAUSE:
			var telegraph_at_sec := (
				G.settings.flathead_pause_sec
				- G.settings.flathead_telegraph_sec
			)
			if not _is_telegraphed and _phase_sec >= telegraph_at_sec:
				_telegraph()
			if _phase_sec >= G.settings.flathead_pause_sec:
				_start_twist()
		Phase.TWIST:
			if _get_twist_progress() >= 1.0:
				_finish_twist()


## A creak and a tensed handle warn of the next twist.
func _telegraph() -> void:
	_is_telegraphed = true
	G.audio.play_sound(&"creak", true)
	var driver := engaged_tool as FlatHeadScrewDriver
	if is_instance_valid(driver):
		driver.tense(G.settings.flathead_telegraph_sec)


func _start_twist() -> void:
	_phase = Phase.TWIST
	_phase_sec = 0.0
	_is_turning_tool = true
	_twist_from_rotation = head.rotation
	_twist_to_rotation = _get_twist_target_rotation(_twists_done + 1)
	_twist_from_slide = slide
	_twist_to_slide = _get_twist_target_slide(_twists_done + 1)
	_twist_drift_px = pick_drift_px(
		_random,
		_drift_sign,
		slip_bias,
		seat_tolerance_px,
		G.settings.flathead_slip_min,
		G.settings.flathead_slip_max,
	)
	_twist_drift_applied_px = 0.0


## Eases the head toward the twist's end, and the screw's slide by the same
## share, so the screw slides only while it turns. The tip takes the same
## share of the twist's drift, so the drift is never sudden.
func _turn_and_drift() -> void:
	var eased := smoothstep(0.0, 1.0, _get_twist_progress())
	head.rotation = lerpf(_twist_from_rotation, _twist_to_rotation, eased)
	slide = lerpf(_twist_from_slide, _twist_to_slide, eased)
	var drift_px := _twist_drift_px * eased
	tip_offset_px += drift_px - _twist_drift_applied_px
	_twist_drift_applied_px = drift_px


func _finish_twist() -> void:
	_twists_done += 1
	head.rotation = _twist_to_rotation
	slide = _twist_to_slide
	if _twists_done < _get_twist_count():
		G.audio.play_sound(&"ratchet", true)
		_phase = Phase.PAUSE
		_phase_sec = 0.0
		_is_telegraphed = false
		return
	_twists_done = 0
	if is_install_mode:
		head.rotation = _home_head_rotation
		install()
	else:
		remove()


## The tip skids out of the slot: a scratch, sparks, and the driver hops
## back to the hand. The screw takes 1 damage and keeps its twists.
func _unseat() -> void:
	var axis := get_slot_axis()
	var direction := axis * signf(tip_offset_px)
	var slot_end := head.global_position + axis * clampf(
		tip_offset_px,
		-seat_tolerance_px,
		seat_tolerance_px,
	)
	_set_in_danger(false)
	G.audio.play_sound(&"skid", true)
	var layer := get_layer()
	if is_instance_valid(layer) and is_instance_valid(layer.art):
		# The scratch starts at the end of the slot and runs the way the tip
		# slipped. It draws under the screws.
		G.level.spawn_decal(
			DecalSpawner.Kind.SKID,
			layer.art,
			slot_end + direction * _SKID_SIZE_PX * 0.5,
			_SKID_SIZE_PX,
			direction,
		)
	sparks.global_position = slot_end
	sparks.restart()
	var driver := engaged_tool
	mode = Mode.UNSTARTED
	release_tool()
	if is_instance_valid(driver):
		driver.ease_follow_offset_from(
			driver.follow_offset + Vector2(0.0, -_UNSEAT_HOP_PX)
		)
	_reset_seat()
	take_damage(1)


## Centers the tip and waits for the next twist.
func _reset_seat() -> void:
	tip_offset_px = 0.0
	_phase = Phase.PAUSE
	_phase_sec = 0.0
	_twist_drift_px = 0.0
	_twist_drift_applied_px = 0.0
	_is_telegraphed = false
	_is_turning_tool = false
	_set_in_danger(false)


## The scrape plays while the tip is near the end of the slot.
func _set_in_danger(is_in_danger: bool) -> void:
	if is_in_danger == _is_in_danger:
		return
	_is_in_danger = is_in_danger
	if is_in_danger:
		# The scrape's rising pitch comes with LX25.
		G.audio.play_sound(&"scrape")
	else:
		G.audio.stop_sound("scrape")


## A small random shake of the tip while it is in danger.
func _get_danger_shake() -> Vector2:
	if not _is_in_danger:
		return Vector2.ZERO
	return Vector2(
		randf_range(-_DANGER_SHAKE_PX, _DANGER_SHAKE_PX),
		randf_range(-_DANGER_SHAKE_PX, _DANGER_SHAKE_PX),
	)


func _get_twist_progress() -> float:
	return minf(_phase_sec / G.settings.flathead_twist_duration_sec, 1.0)


## Twists that finish this screw: out, or back in after install mode.
func _get_twist_count() -> int:
	return install_twists if is_install_mode else twists_needed


## The head's angle at the end of twist number `twist`, counting from 1.
## Taking the screw out turns it counter-clockwise by the twist angle each
## time. Driving it in splits the loose turn evenly, so the last twist
## ends at home.
func _get_twist_target_rotation(twist: int) -> float:
	if is_install_mode:
		return (
			_home_head_rotation
			- LOOSE_TURN_RAD
			+ LOOSE_TURN_RAD * twist / install_twists
		)
	return (
		_home_head_rotation
		- deg_to_rad(G.settings.flathead_twist_angle_deg) * twist
	)


## The screw's slide at the end of twist number `twist`, counting from 1.
## Taking the screw out slides it up an even share per twist, so the last
## twist ends all the way out. Driving it in slides it back down the same
## way, so the last twist ends at home.
func _get_twist_target_slide(twist: int) -> float:
	var share := float(twist) / _get_twist_count()
	return 1.0 - share if is_install_mode else share
