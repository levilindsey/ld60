extends Part
## A gear from the parts drawers. The kind is set here, so
## `gear_part.tscn` needs no `setup()` call to show its art.


func _init() -> void:
	type = Type.GEAR
