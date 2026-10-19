extends Part
## An LED from the parts drawers. The kind is set here, so
## `led_part.tscn` needs no `setup()` call to show its art.


func _init() -> void:
	type = Type.LED
