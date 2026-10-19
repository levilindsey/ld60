extends Part
## A joystick from the parts drawers. The kind is set
## here, so `joystick_part.tscn` needs no `setup()` call to
## show its art.


func _init() -> void:
	type = Type.JOYSTICK
