class_name FlatHeadScrew
extends Screw
## A flathead screw. The flathead microgame comes with LX11
## (docs/design/flathead.md).


## Seconds the stand-in takes to turn the screw out or drive it in.
const _STAND_IN_SEC := 0.4
## How far the stand-in turns a screw counter-clockwise to take it out.
const _REMOVE_TURN_RAD := PI

var _stand_in_tween: Tween


# Stand-in until LX11.
# The screw only turns, never scales: half a turn counter-clockwise to
# come out, and clockwise from its loose angle back home to go in.
func engage(tool: Tool) -> void:
	super.engage(tool)
	G.audio.play_sound("ratchet")
	if is_instance_valid(_stand_in_tween):
		_stand_in_tween.kill()
	_stand_in_tween = create_tween()
	_stand_in_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	if is_install_mode:
		_stand_in_tween.tween_property(
			head,
			"rotation",
			head.rotation + LOOSE_TURN_RAD,
			_STAND_IN_SEC,
		)
		_stand_in_tween.tween_callback(install)
	else:
		_stand_in_tween.tween_property(
			head,
			"rotation",
			head.rotation - _REMOVE_TURN_RAD,
			_STAND_IN_SEC,
		)
		_stand_in_tween.tween_callback(remove)
