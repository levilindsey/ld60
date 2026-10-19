extends Part
## A nut from the parts drawers. The kind is set here, so
## `nut_part.tscn` needs no `setup()` call to show its art.


func _init() -> void:
	type = Type.NUT
