class_name CreditsCard
extends Node2D
## The end card. When the last repairable is done it floats down
## from above the screen and stops in the middle, face-on, with
## the credits on it. The credits state has the tree paused by
## then, so the card runs with process_mode ALWAYS (set in its
## scene) and its drop tween ignores the pause; nothing else on
## the bench can be touched once it is up.


const DROP_DURATION_SEC := 1.6
## Just above the top edge of the 1280x720 view, in level space.
const START_POSITION := Vector2(0.0, -560.0)

var _has_shown := false


## Drops the card from above the screen to the middle. Once
## shown it stays: there is no clicking out of the credits.
func show_credits() -> void:
	if _has_shown:
		return
	_has_shown = true
	position = START_POSITION
	show()
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		self, "position", Vector2.ZERO, DROP_DURATION_SEC
	)
