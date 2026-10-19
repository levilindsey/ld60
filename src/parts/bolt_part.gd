extends Part
## A bolt from the parts drawers. The kind is set here, so
## `bolt_part.tscn` needs no `setup()` call to show its art.


func _init() -> void:
	type = Type.BOLT
