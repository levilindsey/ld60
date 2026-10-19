extends Part
## A circuit from the parts drawers. The kind is set
## here, so `circuit_part.tscn` needs no `setup()` call to
## show its art.


func _init() -> void:
	type = Type.CIRCUIT
