extends Part
## A tube from the parts drawers. The kind is set here, so
## `tube_part.tscn` needs no `setup()` call to show its art.


func _init() -> void:
	type = Type.TUBE
