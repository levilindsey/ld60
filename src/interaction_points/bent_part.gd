class_name BentPart
extends StrikablePoint
## A bent part the hammer knocks back into line (docs/design/
## hammer.md). Each working hit removes a share of the error. A
## hit that is too hard flips the error to the other side.


## The art that sits bent. It turns straight as hits land.
@export var art: Node2D
## Optional straight art swapped in when the part is fixed,
## for a piece whose straight shape is its own sprite (the
## TV antenna). Hidden until the part finishes.
@export var straight_art: Node2D
## How far the part starts bent, in degrees.
@export var error_deg := 18.0
## Working hits that straighten the part.
@export var hits_to_straighten := 3
## At this error or less, the part counts as straight.
@export var done_threshold_deg := 2.0

## The bend left, in degrees. It can go negative on a flip.
var current_error_deg := 0.0

var _home_rotation := 0.0


func _ready() -> void:
	super._ready()
	type = Type.BENT_PART
	role = Role.REPAIR
	G.check(is_instance_valid(art))
	_home_rotation = art.rotation
	current_error_deg = error_deg
	if is_instance_valid(straight_art):
		straight_art.hide()
	_apply_error()


func apply_hit(_strength: float, is_over: bool) -> void:
	current_error_deg *= _get_error_left_share()
	if is_over:
		current_error_deg = -current_error_deg
	if absf(current_error_deg) <= done_threshold_deg:
		current_error_deg = 0.0
		_apply_error()
		if is_instance_valid(straight_art):
			art.hide()
			straight_art.show()
		finish()
	else:
		_apply_error()


func _apply_error() -> void:
	if is_instance_valid(art):
		art.rotation = _home_rotation + deg_to_rad(current_error_deg)


## The share of the error one hit leaves, spread so that
## `hits_to_straighten` hits land on the done threshold.
func _get_error_left_share() -> float:
	var start := maxf(absf(error_deg), done_threshold_deg + 0.01)
	var ratio := clampf(done_threshold_deg / start, 0.0, 1.0)
	return pow(ratio, 1.0 / maxf(float(hits_to_straighten), 1.0))
