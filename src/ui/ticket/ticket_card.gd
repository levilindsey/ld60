class_name TicketCard
extends LiftableProp
## The repair ticket: a paper card with the customer's complaint about the
## item on the bench (docs/design/outbox.md).
##
## When an item arrives, the ticket flutters down onto the desk beside it.
## Tapping it lifts it up to read. A tap anywhere outside it sets it
## back down.
## The card's paper and text render into a SubViewport, so the whole card
## can be drawn in perspective while it rests.


enum State {
	AWAY,
	FALLING,
	RESTING,
	LIFTING,
	OPEN,
	LOWERING,
	LEAVING,
}


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
const _LEAVE_DURATION_SEC := 0.35
## How far the ticket rises as it fades away.
const _LEAVE_RISE_PX := 60.0


var state := State.AWAY

var _is_leave_requested := false
var _motion_tween_id := -1


func _ready() -> void:
	%Display.texture = %ContentViewport.get_texture()
	%DisplayShadow.texture = %Display.texture
	super()
	visible = false


## Drops the ticket onto the desk with the customer's complaint. A ticket
## that is still showing swaps its text and drops again.
func show_item(complaint: String) -> void:
	%ComplaintLabel.text = complaint
	_stop_motion()
	_is_leave_requested = false
	modulate.a = 1.0
	visible = true
	state = State.FALLING
	_set_fall(0.0)
	reset_physics_interpolation()
	_motion_tween_id = G.time.tween_method(
		self,
		"_set_fall",
		0.0,
		1.0,
		_FALL_DURATION_SEC,
		"linear",
		0.0,
		TimeType.APP_PHYSICS,
		_on_landed,
	)


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
	if _is_leave_requested:
		_leave()
	else:
		state = State.RESTING


func _lift() -> void:
	state = State.LIFTING
	_set_resting_order(false)
	_play_sound(&"card_pickup")
	_tween_lift(0.0, 1.0, _on_lifted)


func _on_lifted() -> void:
	if _is_leave_requested:
		_lower()
		return
	state = State.OPEN


func _lower() -> void:
	state = State.LOWERING
	_play_sound(&"card_land")
	_tween_lift(1.0, 0.0, _on_lowered)


func _on_lowered() -> void:
	_set_resting_order(true)
	if _is_leave_requested:
		_leave()
	else:
		state = State.RESTING


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
		TimeType.APP_PHYSICS,
		_on_left,
	)


func _on_left() -> void:
	visible = false
	state = State.AWAY
	_is_leave_requested = false


func _stop_motion() -> void:
	G.time.clear_tween(_motion_tween_id)
	_motion_tween_id = -1
	_stop_lift()


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


## 0 rests on the desk spot; 1 has risen and faded away.
func _set_leave(progress: float) -> void:
	_set_lift(0.0)
	global_position.y -= _LEAVE_RISE_PX * progress
	modulate.a = 1.0 - progress
