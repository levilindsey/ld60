extends Part
## A spring from the parts drawers. The kind is set here, so
## `spring_part.tscn` needs no `setup()` call to show its art.


func _init() -> void:
	type = Type.SPRING
