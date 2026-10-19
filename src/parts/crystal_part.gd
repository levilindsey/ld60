extends Part
## A crystal from the parts drawers. The kind is set
## here, so `crystal_part.tscn` needs no `setup()` call to
## show its art.


func _init() -> void:
	type = Type.CRYSTAL
