class_name DropShadow
extends Node2D
## A bench shadow under a thing that is resting there. Two kinds:
##
## - ELLIPSE: a soft ellipse of `size_px`, in world pixels.
## - SILHOUETTE: dark copies of the host's sprites, drawn again
##   offset in eight directions so a rim peeks out evenly on
##   every side of the shape, following the host's position and
##   rotation. Optionally clipped to the part of the shape at
##   and below a holder's contact point (a tool resting on its
##   shoulders: only what hangs below the neck shadows).
##
## Sizes and offsets are world pixels: the drawing compensates
## for any scale above it, the same lesson the outline hint
## learned, so a scaled-down prop does not shrink its shadow.
## Only shown while its `show_when` callable says the host is at
## rest and not being held or carried, fading in and out.


enum Kind {
	ELLIPSE,
	SILHOUETTE,
}

## Rim layers for silhouettes: (rim distance in world pixels,
## alpha share). Each rim layer draws the shape offset in eight
## directions at that distance, widening every part of the shape
## by the same amount: a thin shaft gets as much rim on each side
## as a wide handle. (Scaling the shape up instead barely widens
## its thin parts, and a percentage of the texture canvas is
## mostly transparent padding.) The wider, fainter rim behind
## fakes a blur; the last layer is the shape itself.
const _RIM_LAYERS: Array = [[9.0, 0.45], [4.0, 0.7], [0.0, 0.85]]
const _RIM_STEP := 0.7071
const _CLIP_SHADER := """
shader_type canvas_item;
uniform vec2 holder_pos = vec2(0.0, 0.0);
uniform vec2 holder_axis = vec2(0.0, 1.0);
uniform float clip_enabled = 0.0;
varying vec2 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	if (
		clip_enabled > 0.5
		&& dot(world_pos - holder_pos, holder_axis) < 0.0
	) {
		discard;
	}
	COLOR = vec4(0.0, 0.0, 0.0, texture(TEXTURE, UV).a * COLOR.a);
}
"""

## World size of the ellipse (ELLIPSE kind).
var size_px := Vector2(60.0, 18.0)
## World offset from the host's origin to the shadow's centre.
var offset_px := Vector2(4.0, 10.0)
## Judges whether the host is at rest and unheld right now.
var show_when: Callable
## Seconds the shadow takes to fade in or out when its host is
## picked up or set down. It never just appears or vanishes.
var fade_sec := 0.18
## Which kind of shadow this is.
var kind := Kind.ELLIPSE:
	set(value):
		kind = value
		_rebuild()
## When set, silhouette fragments on the up side of this node
## (against the host's local down axis) are clipped away. Set it
## to a tool's holder shape while the tool rests in its holder;
## clear it (null) for the full shape.
var clip_holder: Node2D:
	set(value):
		clip_holder = value
		_update_clip()
## When set, the shadow centres on this node instead of the host
## (an ellipse aligned with a tool's holder contact, say).
var anchor: Node2D
## Silhouette copies are drawn at this fraction of the shape's
## size (below 1 makes a shadow smaller than its host).
var size_scale := 1.0

var _host: CanvasItem
var _fade := 0.0
var _layers: Array[Node2D] = []
var _copies: Array = []
var _clip_material: ShaderMaterial


## Attaches an ellipse shadow to `host` and returns it.
static func attach(
	host: CanvasItem,
	shadow_size: Vector2,
	shadow_offset: Vector2,
	should_show: Callable,
) -> DropShadow:
	var shadow := _make(host, shadow_offset, should_show)
	shadow.size_px = shadow_size
	return shadow


## Attaches a silhouette shadow built from `sources` (the host's
## sprites; the host itself when empty) and returns it.
static func attach_silhouette(
	host: CanvasItem,
	sources: Array,
	shadow_offset: Vector2,
	should_show: Callable,
	p_size_scale := 1.0,
) -> DropShadow:
	var shadow := _make(host, shadow_offset, should_show)
	shadow._pending_sources = sources
	shadow.size_scale = p_size_scale
	shadow.kind = Kind.SILHOUETTE
	return shadow


static func _make(
	host: CanvasItem,
	shadow_offset: Vector2,
	should_show: Callable,
) -> DropShadow:
	var shadow := DropShadow.new()
	shadow._host = host
	shadow.offset_px = shadow_offset
	shadow.show_when = should_show
	host.add_sibling.call_deferred(shadow)
	# Sit immediately behind the host in the draw order.
	host.get_parent().move_child.call_deferred(
		shadow,
		host.get_index(),
	)
	# No tree_exiting cleanup here: hosts get reparented (a screw's
	# bench art leaves its hole), and that must not kill the shadow.
	# _process frees the shadow once the host itself is gone.
	return shadow


var _pending_sources: Array = []


## How many sprite copies the silhouette is built from.
func get_copy_count() -> int:
	return _copies.size()


func _process(delta: float) -> void:
	if not is_instance_valid(_host):
		queue_free()
		return
	var centre: Vector2 = (_host as Node2D).global_position
	if is_instance_valid(anchor):
		centre = anchor.global_position
	global_position = centre + offset_px
	global_rotation = (_host as Node2D).global_rotation
	_sync_silhouette()
	_update_clip()
	var should_show := (
		_host.is_visible_in_tree()
		and show_when.is_valid()
		and bool(show_when.call())
	)
	var target := 1.0 if should_show else 0.0
	if not is_equal_approx(_fade, target):
		_fade = move_toward(
			_fade,
			target,
			delta / maxf(fade_sec, 0.01),
		)
	visible = _fade > 0.01
	if visible:
		queue_redraw()


func _draw() -> void:
	if kind != Kind.ELLIPSE and not _copies.is_empty():
		return
	# Radii in local units that come out as world pixels, whatever
	# scale this node sits under.
	var basis := get_global_transform()
	var scale_x := maxf(basis.basis_xform(Vector2(1.0, 0.0)).length(), 0.0001)
	var scale_y := maxf(basis.basis_xform(Vector2(0.0, 1.0)).length(), 0.0001)
	var radii := Vector2(
		size_px.x / (2.0 * scale_x),
		size_px.y / (2.0 * scale_y),
	)
	var points := PackedVector2Array()
	const SEGMENTS := 24
	for index in SEGMENTS:
		var angle := TAU * float(index) / SEGMENTS
		points.append(Vector2(cos(angle), sin(angle)) * radii)
	draw_colored_polygon(
		points,
		Color(0.0, 0.0, 0.0, _get_alpha() * _fade),
	)


func _get_alpha() -> float:
	if is_instance_valid(G.settings):
		return G.settings.drop_shadow_alpha
	return 0.45


## (Re)builds the silhouette copies from the host's sprites.
func _rebuild() -> void:
	for layer in _layers:
		layer.queue_free()
	_layers.clear()
	_copies.clear()
	if kind != Kind.SILHOUETTE or not is_instance_valid(_host):
		return
	var sources: Array = _pending_sources.duplicate()
	if sources.is_empty():
		if _host is Sprite2D or _host is AnimatedSprite2D:
			sources.append(_host)
		else:
			_collect_sprites(_host, sources)
	if sources.is_empty():
		return
	if not is_instance_valid(_clip_material):
		_clip_material = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = _CLIP_SHADER
		_clip_material.shader = shader
	for rim in _RIM_LAYERS:
		var layer := Node2D.new()
		add_child(layer)
		_layers.append(layer)
		for source in sources:
			for offset in _rim_offsets(float(rim[0])):
				var copy: CanvasItem = _make_copy(source)
				if not is_instance_valid(copy):
					continue
				if copy is Sprite2D or copy is AnimatedSprite2D:
					copy.material = _clip_material
				layer.add_child(copy)
				_copies.append(
					[
						copy,
						source,
						float(rim[1]),
						(copy as Node2D).scale,
						(copy as Node2D).position,
						offset,
					],
				)
	_update_clip()


## The world-pixel offsets one rim layer draws the shape at:
## eight directions at `distance`, or just the shape itself
## when the distance is zero.
func _rim_offsets(distance: float) -> Array[Vector2]:
	if distance <= 0.0:
		return [Vector2.ZERO]
	var diag := distance * _RIM_STEP
	return [
		Vector2(distance, 0.0),
		Vector2(-distance, 0.0),
		Vector2(0.0, distance),
		Vector2(0.0, -distance),
		Vector2(diag, diag),
		Vector2(diag, -diag),
		Vector2(-diag, diag),
		Vector2(-diag, -diag),
	]


func _collect_sprites(node: Node, into: Array) -> void:
	for child in node.get_children():
		if child is DropShadow:
			continue
		if (
			child is Sprite2D
			or child is AnimatedSprite2D
			or child is Polygon2D
		):
			into.append(child)
		_collect_sprites(child, into)


## A black copy of a sprite or polygon, in its local pose under
## the host, so the layer (given the host's global transform)
## draws it where the host draws it.
func _make_copy(source: CanvasItem) -> CanvasItem:
	var copy: CanvasItem
	if source is Polygon2D:
		var polygon_copy := Polygon2D.new()
		var polygon_source := source as Polygon2D
		polygon_copy.polygon = polygon_source.polygon
		polygon_copy.offset = polygon_source.offset
		copy = polygon_copy
	elif source is AnimatedSprite2D:
		var animated_copy := AnimatedSprite2D.new()
		var animated_source := source as AnimatedSprite2D
		animated_copy.sprite_frames = animated_source.sprite_frames
		animated_copy.animation = animated_source.animation
		animated_copy.frame = animated_source.frame
		copy = animated_copy
	elif source is Sprite2D:
		var sprite_copy := Sprite2D.new()
		var sprite_source := source as Sprite2D
		sprite_copy.texture = sprite_source.texture
		sprite_copy.region_enabled = sprite_source.region_enabled
		sprite_copy.region_rect = sprite_source.region_rect
		sprite_copy.frame = sprite_source.frame
		sprite_copy.frame_coords = sprite_source.frame_coords
		sprite_copy.hframes = sprite_source.hframes
		sprite_copy.vframes = sprite_source.vframes
		copy = sprite_copy
	else:
		return null
	# Pose relative to the host, not to the sprite's parent.
	var relative := (
		_host.get_global_transform().affine_inverse()
		* source.get_global_transform()
	)
	copy.position = relative.origin
	copy.rotation = relative.get_rotation()
	copy.scale = relative.get_scale()
	if copy is Sprite2D:
		(copy as Sprite2D).centered = (source as Sprite2D).centered
		(copy as Sprite2D).offset = (source as Sprite2D).offset
		(copy as Sprite2D).flip_h = (source as Sprite2D).flip_h
		(copy as Sprite2D).flip_v = (source as Sprite2D).flip_v
	elif copy is AnimatedSprite2D:
		(copy as AnimatedSprite2D).centered = (
			source as AnimatedSprite2D
		).centered
		(copy as AnimatedSprite2D).offset = (
			source as AnimatedSprite2D
		).offset
		(copy as AnimatedSprite2D).flip_h = (
			source as AnimatedSprite2D
		).flip_h
		(copy as AnimatedSprite2D).flip_v = (
			source as AnimatedSprite2D
		).flip_v
	copy.modulate = Color(0.0, 0.0, 0.0, 0.0)
	return copy


## Keeps the silhouette matched to the host: transform per rim
## layer, per-copy visibility, animation frames and darkness.
## Each copy sits at its built pose plus its rim offset, converted
## from world pixels into the layer's space so the rim is the
## same width whatever the host is scaled by.
func _sync_silhouette() -> void:
	if kind != Kind.SILHOUETTE or _copies.is_empty():
		return
	var host_transform := _host.get_global_transform()
	for layer in _layers:
		layer.global_transform = Transform2D(
			host_transform.x,
			host_transform.y,
			global_position,
		)
	var to_layer := host_transform.affine_inverse()
	for pair in _copies:
		var copy := pair[0] as CanvasItem
		var source := pair[1] as CanvasItem
		copy.scale = (pair[3] as Vector2) * size_scale
		copy.position = (pair[4] as Vector2) + to_layer.basis_xform(
			pair[5] as Vector2,
		)
		copy.visible = source.is_visible_in_tree() and _host.visible
		if copy is Polygon2D and source is Polygon2D:
			var polygon_copy := copy as Polygon2D
			var polygon_source := source as Polygon2D
			if polygon_copy.polygon != polygon_source.polygon:
				polygon_copy.polygon = polygon_source.polygon
		if copy is AnimatedSprite2D and source is AnimatedSprite2D:
			(copy as AnimatedSprite2D).animation = (
				source as AnimatedSprite2D
			).animation
			(copy as AnimatedSprite2D).frame = (
				source as AnimatedSprite2D
			).frame
		copy.modulate = Color(
			0.0,
			0.0,
			0.0,
			_get_alpha() * _fade * float(pair[2]),
		)


func _update_clip() -> void:
	if not is_instance_valid(_clip_material):
		return
	var is_clipped := is_instance_valid(clip_holder)
	_clip_material.set_shader_parameter(
		"clip_enabled",
		1.0 if is_clipped else 0.0,
	)
	if is_clipped:
		# Keep the shape on the holder's own down side: past the
		# contact point along the host's local down axis, whatever
		# way the host is turned.
		_clip_material.set_shader_parameter(
			"holder_pos",
			clip_holder.global_position,
		)
		_clip_material.set_shader_parameter(
			"holder_axis",
			_host.get_global_transform().y.normalized(),
		)
