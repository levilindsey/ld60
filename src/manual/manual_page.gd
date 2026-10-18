class_name ManualPage
extends Node2D
## One inner page of the instruction manual. The outline art is shared by
## every page on the same side; only the content texture changes.


## The page outline art. Left and right pages use mirrored outlines, with
## the binding on the spine side.
@export var outline: Texture2D


func _ready() -> void:
	%Outline.texture = outline


func set_content(texture: Texture2D) -> void:
	%Content.texture = texture
	%Content.visible = texture != null
