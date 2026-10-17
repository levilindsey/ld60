class_name FlatHeadScrewDriver
extends Tool


var in_use_angle_deg := 125.0


func _set_mode(to_mode: Mode) -> void:
	super._set_mode(to_mode)
	match to_mode:
		Mode.IN_USE:
			_set_rotation(deg_to_rad(in_use_angle_deg))
