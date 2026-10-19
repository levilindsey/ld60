extends Part
## TV controls from the parts drawers. The kind is set
## here, so `tv_controls_part.tscn` needs no `setup()` call
## to show its art.


func _init() -> void:
	type = Type.TV_CONTROLS
