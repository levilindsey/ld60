class_name TicketCard
extends LiftableProp
## The repair ticket: a paper card with the customer's complaint about the
## item on the bench (docs/design/outbox.md).
##
## When an item arrives, the ticket flutters down onto the desk beside it.
## Tapping it lifts it up to read. A tap anywhere outside it sets it
## back down.
##
## Once the item ships, the ticket is the receipt: it lifts to `done_spot`,
## the repair time writes itself in by hand, a stamp rates the repair, and
## the ticket leaves. A tap skips to the end.
##
## The card's paper and text render into a SubViewport, so the whole card
## can be drawn in perspective while it rests.


## The receipt is done and the ticket has left.
signal done_closed


enum State {
	AWAY,
	FALLING,
	RESTING,
	LIFTING,
	OPEN,
	LOWERING,
	LEAVING,
	## Lifted as the receipt, writing the time and stamping.
	SHOWING_DONE,
}


## The beat every ticket waits after its item lands before it
## comes in.
const _CARD_DELAY_SEC := 0.3
## The radio's ticket waits this much longer on top of that.
const _FLING_EXTRA_DELAY_SEC := 0.3
const _FALL_DURATION_SEC := 1.8
## How high above its desk spot the ticket starts falling.
const _FALL_HEIGHT_PX := 700.0
## How far the ticket sways side to side as it falls.
const _FALL_SWAY_PX := 125.0
const _FALL_SWAY_CYCLES := 2.0
## How much the ticket rises at the ends of each swing, like a pendulum.
const _FALL_SWING_LIFT_PX := 25.0
## How far the ticket rocks as it falls.
const _FALL_ROCK_RADIANS := 0.35
const _FLING_DURATION_SEC := 0.9
## How far below its desk spot the ticket starts its toss.
const _FLING_DEPTH_PX := 600.0
## How far left of its desk spot the toss starts, gliding
## right as it rises.
const _FLING_FROM_LEFT_PX := 420.0
## How high above its desk spot the toss peaks.
const _FLING_PEAK_PX := 120.0
## How far the ticket spins on the way up, settling flat as it lands.
const _FLING_SPIN_RADIANS := -1.2
const _LEAVE_DURATION_SEC := 0.35
## How far the ticket rises as it fades away.
const _LEAVE_RISE_PX := 60.0
const _WRITE_LETTERS_PER_SEC := 12.0
## The pause between the time being written and the stamp.
const _STAMP_DELAY_SEC := 0.3
## How long the ticket jolts and settles when the stamp is slapped on.
const _SLAP_DURATION_SEC := 0.35
## How far the slap pushes the ticket down, in pixels.
const _SLAP_PUSH_PX := 10.0
## How much the slap squashes the ticket, as a fraction of its size.
const _SLAP_SQUASH := 0.04
const _SLAP_ROCK_RADIANS := 0.03
## Bounces as the ticket settles from the slap.
const _SLAP_BOUNCES := 2.5
## How long the finished receipt stays before it leaves.
const _DONE_HOLD_SEC := 4.0
## The complaint's font size, and the smallest it shrinks to so a long
## complaint still fits on the paper.
const _COMPLAINT_FONT_SIZE := 40
const _COMPLAINT_MIN_FONT_SIZE := 24


## The pose the ticket lifts to as the receipt.
@export var done_spot: Node2D
## The rating stamps, worst first: oof, ok, great. A missing one stamps
## nothing.
@export var stamp_textures: Array[Texture2D] = []


var state := State.AWAY

var _is_leave_requested := false
var _is_done_requested := false
## True once the receipt is up and a tap can skip it.
var _is_done_shown := false
var _motion_tween_id := -1
var _timeout_id := -1
## The lift the ticket leaves from: 0 on the desk, 1 as the receipt.
var _leave_lift := 0.0
## Letters in the written time.
var _time_letter_count := 0


func _ready() -> void:
	%Display.texture = %ContentViewport.get_texture()
	%DisplayShadow.texture = %Display.texture
	super()
	visible = false


## Drops the ticket onto the desk with the customer's complaint, or tosses
## it up from below when `flings_up`. A ticket that is still showing swaps
## its text and drops again. Words in braces, like `{darn}`, are scribbled
## out.
func show_item(complaint: String, flings_up := false) -> void:
	_set_complaint(complaint)
	_fit_complaint()
	%TimeLabel.text = ""
	%Stamp.visible = false
	_stop_motion()
	_is_leave_requested = false
	modulate.a = 1.0
	visible = true
	state = State.FALLING
	var motion := "_set_fling" if flings_up else "_set_fall"
	call(motion, 0.0)
	reset_physics_interpolation()
	# Every ticket waits a beat before it comes in; the
	# radio's waits a little longer.
	var delay := _CARD_DELAY_SEC
	if flings_up:
		delay += _FLING_EXTRA_DELAY_SEC
	_motion_tween_id = G.time.tween_method(
		self,
		motion,
		0.0,
		1.0,
		_FLING_DURATION_SEC if flings_up else _FALL_DURATION_SEC,
		"linear",
		delay,
		TimeType.PLAY_PHYSICS,
		_on_landed,
	)


## Shows the ticket as the receipt: it lifts to `done_spot`, the time
## writes in, and the stamp for the rating (1 to 3) comes down. Emits
## `done_closed` once the ticket has left.
func show_done(repair_time_sec: float, star_count: int) -> void:
	var time_text := _get_fixed_time_text(repair_time_sec)
	_time_letter_count = time_text.length()
	%TimeLabel.text = "[ink]%s[/ink]" % time_text
	_set_ink_progress(0.0)
	%Stamp.visible = false
	var stamp_index := star_count - 1
	%Stamp.texture = (
		stamp_textures[stamp_index]
		if stamp_index >= 0 and stamp_index < stamp_textures.size()
		else null
	)
	_is_leave_requested = false
	match state:
		State.AWAY, State.LEAVING:
			done_closed.emit.call_deferred()
		State.RESTING:
			_lift_to_done()
		State.OPEN:
			_is_done_requested = true
			_lower()
		_:
			# The motion in progress checks the request when it finishes.
			_is_done_requested = true


## Sends the ticket away, setting it down first if it's open.
func hide_card() -> void:
	if state == State.AWAY or state == State.LEAVING:
		return
	_is_leave_requested = true
	match state:
		State.RESTING:
			_leave()
		State.OPEN:
			_lower()
		_:
			# The motion in progress checks the request when it finishes.
			pass


func _handle_press(event: InputEventMouseButton) -> bool:
	if state == State.AWAY or state == State.LEAVING:
		return false
	if state == State.SHOWING_DONE:
		# The receipt takes every tap, and a tap once it's up skips it.
		if _is_done_shown:
			_finish_done()
		return true
	if state == State.OPEN and not _is_on_warped_sprite(event):
		# Open and tapped outside: set the ticket back down. The tap
		# is spent, so it doesn't also press the bench behind.
		_lower()
		return true
	if not _is_on_warped_sprite(event):
		return false
	if state == State.RESTING:
		_lift()
	return true


func _on_landed() -> void:
	_play_sound(&"card_land")
	_continue_on_desk()


## The ticket is on the desk: it carries out a request that came in while
## it moved, or rests.
func _continue_on_desk() -> void:
	if _is_done_requested:
		_lift_to_done()
	elif _is_leave_requested:
		_leave()
	else:
		state = State.RESTING


func _lift() -> void:
	state = State.LIFTING
	_set_resting_order(false)
	_play_sound(&"card_pickup")
	_tween_lift(0.0, 1.0, _on_lifted)


func _on_lifted() -> void:
	if _is_leave_requested or _is_done_requested:
		_lower()
		return
	state = State.OPEN


func _lower() -> void:
	state = State.LOWERING
	_play_sound(&"card_land")
	_tween_lift(1.0, 0.0, _on_lowered)


func _on_lowered() -> void:
	_set_resting_order(true)
	_continue_on_desk()


func _lift_to_done() -> void:
	state = State.SHOWING_DONE
	_is_done_requested = false
	_is_done_shown = false
	_lift_spot = done_spot
	_set_resting_order(false)
	_play_sound(&"card_pickup")
	_tween_lift(0.0, 1.0, _write_time)


func _write_time() -> void:
	_is_done_shown = true
	_play_sound(&"scrawling", true)
	var fade_letters: float = %TimeLabel.custom_effects[0].fade_letters
	_motion_tween_id = G.time.tween_method(
		self,
		"_set_ink_progress",
		0.0,
		_time_letter_count + fade_letters,
		_time_letter_count / _WRITE_LETTERS_PER_SEC,
		"linear",
		0.0,
		TimeType.PLAY_PHYSICS,
		_on_time_written,
	)


func _on_time_written() -> void:
	if %Stamp.texture == null:
		_hold_done()
		return
	_timeout_id = G.time.set_timeout(
		_stamp,
		_STAMP_DELAY_SEC,
		[],
		TimeType.PLAY_PHYSICS,
	)


## The stamp appears all at once and the ticket jolts, as if slapped.
func _stamp() -> void:
	%Stamp.visible = true
	_play_sound(&"thud", true)
	_motion_tween_id = G.time.tween_method(
		self,
		"_set_slap",
		0.0,
		1.0,
		_SLAP_DURATION_SEC,
		"linear",
		0.0,
		TimeType.PLAY_PHYSICS,
		_hold_done,
	)


func _hold_done() -> void:
	_timeout_id = G.time.set_timeout(
		_finish_done,
		_DONE_HOLD_SEC,
		[],
		TimeType.PLAY_PHYSICS,
	)


## Shows the finished receipt at once, then sends the ticket away.
func _finish_done() -> void:
	_stop_motion()
	_set_ink_progress(_time_letter_count + 2.0)
	if %Stamp.texture != null:
		%Stamp.visible = true
	_set_lift(1.0)
	_is_done_shown = false
	_leave_lift = 1.0
	_leave()


func _leave() -> void:
	state = State.LEAVING
	_play_sound(&"card_pickup")
	_motion_tween_id = G.time.tween_method(
		self,
		"_set_leave",
		0.0,
		1.0,
		_LEAVE_DURATION_SEC,
		"ease_in",
		0.0,
		TimeType.PLAY_PHYSICS,
		_on_left,
	)


func _on_left() -> void:
	visible = false
	var was_done := is_equal_approx(_leave_lift, 1.0)
	state = State.AWAY
	_is_leave_requested = false
	_leave_lift = 0.0
	_lift_spot = open_spot
	# The next ticket falls and rests behind the tools.
	_set_resting_order(true)
	if was_done:
		done_closed.emit()


func _stop_motion() -> void:
	G.time.clear_tween(_motion_tween_id)
	_motion_tween_id = -1
	G.time.clear_timeout(_timeout_id)
	_timeout_id = -1
	_stop_lift()


## Shows a complaint, with its `{braced}` words written without the
## braces and scribbled over.
func _set_complaint(complaint: String) -> void:
	var text := ""
	var scribble_ranges: Array[Vector2i] = []
	var scribble_start := -1
	for character in complaint:
		if character == "{":
			scribble_start = text.length()
		elif character == "}" and scribble_start >= 0:
			scribble_ranges.append(Vector2i(scribble_start, text.length()))
			scribble_start = -1
		else:
			text += character
	%ComplaintLabel.text = text
	%Scribbles.ranges = scribble_ranges


## Shrinks the complaint's font until it fits in its area.
func _fit_complaint() -> void:
	var font: Font = %ComplaintLabel.get_theme_font(&"font")
	var area: Vector2 = %Contents.size
	var font_size := _COMPLAINT_FONT_SIZE
	while font_size > _COMPLAINT_MIN_FONT_SIZE:
		var text_size := font.get_multiline_string_size(
			%ComplaintLabel.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			area.x,
			font_size,
		)
		if text_size.y <= area.y:
			break
		font_size -= 2
	%ComplaintLabel.add_theme_font_size_override(&"font_size", font_size)


func _set_ink_progress(progress: float) -> void:
	%TimeLabel.custom_effects[0].progress = progress


## 0 is the moment of the slap, pushed down and squashed; 1 has settled
## back into the receipt pose, bouncing less and less on the way.
func _set_slap(progress: float) -> void:
	_set_lift(1.0)
	var remaining := 1.0 - progress
	var bounce := (
		remaining * remaining * cos(progress * PI * 2.0 * _SLAP_BOUNCES)
	)
	global_position.y += _SLAP_PUSH_PX * bounce
	global_scale *= 1.0 - _SLAP_SQUASH * bounce
	global_rotation += _SLAP_ROCK_RADIANS * bounce


## "Fixed in 2 min 12 sec", leaving out a unit that is zero.
func _get_fixed_time_text(time_sec: float) -> String:
	var total_sec := roundi(time_sec)
	var minutes := total_sec / 60
	var seconds := total_sec % 60
	var parts: Array[String] = []
	if minutes > 0:
		parts.append("%d min" % minutes)
	if seconds > 0 or minutes == 0:
		parts.append("%d sec" % seconds)
	return "Fixed in %s" % " ".join(parts)


## 0 is high above the desk spot; 1 has landed on it. The ticket swings
## side to side like a pendulum, rising at the ends of each swing and
## leaning into it, and swings less as it settles.
func _set_fall(progress: float) -> void:
	_set_lift(0.0)
	var remaining := 1.0 - smoothstep(0.0, 1.0, progress)
	var swing_angle := TAU * _FALL_SWAY_CYCLES * progress
	global_position += remaining * Vector2(
		_FALL_SWAY_PX * sin(swing_angle),
		-_FALL_HEIGHT_PX + _FALL_SWING_LIFT_PX * cos(2.0 * swing_angle),
	)
	global_rotation += _FALL_ROCK_RADIANS * cos(swing_angle) * remaining


## 0 is below the desk spot and left of it, off screen; 1 has
## landed on it. The ticket flies up past its spot like a
## thrown thing, spinning, gliding right as it rises, peaks at
## `_FLING_PEAK_PX` and drops back onto it.
func _set_fling(progress: float) -> void:
	_set_lift(0.0)
	# The parabola from the depth to the spot whose top is the peak.
	var depth := _FLING_DEPTH_PX
	var gravity := (
		depth + 2.0 * _FLING_PEAK_PX
		+ sqrt(pow(depth + 2.0 * _FLING_PEAK_PX, 2.0) - depth * depth)
	)
	var launch := -depth - gravity
	global_position.y += gravity * progress * progress + launch * progress + depth
	global_position.x -= (
		_FLING_FROM_LEFT_PX * pow(1.0 - progress, 2.0)
	)
	global_rotation += _FLING_SPIN_RADIANS * pow(1.0 - progress, 2.0)


## 0 is where the ticket left from; 1 has risen and faded away.
func _set_leave(progress: float) -> void:
	_set_lift(_leave_lift)
	global_position.y -= _LEAVE_RISE_PX * progress
	modulate.a = 1.0 - progress
