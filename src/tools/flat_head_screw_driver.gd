class_name FlatHeadScrewDriver
extends Tool


var in_use_angle_deg := 125.0


func _set_mode(to_mode: Mode, from_mode: Mode) -> void:
	super._set_mode(to_mode, from_mode)
	match to_mode:
		Mode.IN_USE:
			tween_rotation(deg_to_rad(in_use_angle_deg), Tween.EASE_IN_OUT)
