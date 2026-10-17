class_name ManualPage
extends Node2D
## One inner page of the instruction manual. The outline art is shared by
## every page; only the content texture changes.


func set_content(texture: Texture2D) -> void:
	%Content.texture = texture
	%Content.visible = texture != null
