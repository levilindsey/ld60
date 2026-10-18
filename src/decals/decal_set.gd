class_name DecalSet
extends Resource
## One kind of runtime decal: the pictures to pick from and how each spawn
## varies. `DecalSpawner` holds one of these for each `DecalSpawner.Kind`.
##
## Don't name a class `Decal`: Godot already has a 3D node with that name.


## Each spawn picks one of these at random. Keep the source images small
## (64 to 256 px). The longer side of the picture is drawn `size` pixels
## long, so draw long marks along the x axis.
@export var textures: Array[Texture2D] = []

## Each spawn multiplies its `size` by a random number in this range (x is
## the least, y the most). Use (1, 1) for an exact size.
@export var scale_range: Vector2 = Vector2(0.85, 1.15)

## If true, the decal's x axis points along the spawn's `direction`, as a
## skid follows the slip. If false, the rotation is random.
@export var is_aligned_to_direction: bool = false

## If false, the decal keeps the orientation it was drawn in, in the
## part's own frame, instead of a random spin. Scratches use this: they
## run vertically, with the thick initial-contact end at the bottom.
## Glue uses it too: its strings run vertically. Such a set should also
## turn off `can_flip_vertically`, or half the spawns land upside down.
@export var has_random_rotation: bool = true

## Each flip happens on half of the spawns when it is allowed.
@export var can_flip_horizontally: bool = false
@export var can_flip_vertically: bool = true

## Multiplies the picture's colors. White leaves the art as it is.
@export var tint: Color = Color.WHITE

## Optional. A `CanvasItemMaterial` with `BLEND_MODE_MUL` darkens what is
## under the decal instead of covering it, for dust, grime and rust.
@export var blend_material: Material
