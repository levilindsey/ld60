extends Part
## A letter key from the parts drawers. The kind is set
## here, so `letter_key_part.tscn` needs no `setup()` call
## to show its art.


func _init() -> void:
	type = Type.LETTER_KEY
