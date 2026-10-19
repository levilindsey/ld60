class_name TVRepairable
extends Repairable
## The TV. Its screen plays the two static frames in
## alternation until the set is fixed, then the two fixed
## channel frames, at four frames a second either way.


## Frames of screen noise, before the fix.
@export var static_frames: Array[Texture2D] = []
## Frames of the fixed channel, after the fix.
@export var fixed_frames: Array[Texture2D] = []
## The screen sprite the frames play on.
@export var screen: Sprite2D

## Seconds each screen frame stays up (four a second).
const _FRAME_SEC := 0.25

var _frame_time := 0.0
var _frame_index := 0


func _ready() -> void:
	super._ready()
	_show_frame()


func _process(delta: float) -> void:
	# _process, not _physics_process: the item turns its
	# physics processing off until it lands, and the screen
	# is purely visual.
	if not is_instance_valid(screen):
		return
	_frame_time += delta
	if _frame_time < _FRAME_SEC:
		return
	_frame_time = fmod(_frame_time, _FRAME_SEC)
	_frame_index = (_frame_index + 1) % 2
	_show_frame()


func _show_frame() -> void:
	var frames := fixed_frames if has_finished else static_frames
	if frames.is_empty():
		return
	screen.texture = frames[_frame_index % frames.size()]
