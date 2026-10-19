class_name DropShadow
extends Node2D
## A bench shadow under a thing that is resting there. Two kinds:
##
## - ELLIPSE: a soft ellipse of `size_px`, in world pixels.
## - SILHOUETTE: dark copies of the host's sprites, scaled up a
##   little about the art's centre so a rim peeks out on every
##   side, following the host's position and rotation.
##   Optionally clipped to the part of the shape at and below a
##   holder's contact point (a tool resting on its shoulders:
##   only what hangs below the neck shadows).
##
## Sizes and offset lengths are world pixels: the drawing
## compensates for any scale above it, the same lesson the
## outline hint learned, so a scaled-down prop does not shrink
## its shadow. The offset stays in the world frame (see
## `offset_px`): the light is above, so the shadow always
## sits down-screen from the host. A silhouette's shape still
## turns with the host so it matches the rotated sprite.
## Only shown while its `show_when` callable says the host is at
## rest and not being held or carried, fading in and out.


enum Kind {
	ELLIPSE,
	SILHOUETTE,
}

## Grow layers for silhouettes: (horizontal margin, vertical
## margin, alpha share), in world pixels the scaled copy extends
## past the art. Non-uniform on purpose: a lot of scale
## horizontally so the rim shows on the left and right, only a
## tiny bit vertically. The bigger, fainter copy behind fakes a
## blur. Margins are measured on the art's used
## (non-transparent) rect, not the whole texture canvas: the art
## sits in mostly transparent padding, and a percentage of the
## canvas would barely grow the art itself.
const _GROW_LAYERS: Array = [[20.0, 3.0, 0.45], [10.0, 1.5, 0.8]]
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
## Offset from the host's origin to the shadow's centre, in
## the world frame. It does not turn with the host, so the
## shadow always bears down-screen from the screw, part or
## piece however that thing is turned. Its length is in
## world pixels.
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
## Draw only the darkest grow layer, for hosts where the two
## layers read as two separate shadows (the screws).
var single_layer := false

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
	p_single_layer := false,
) -> DropShadow:
	var shadow := _make(host, shadow_offset, should_show)
	shadow._pending_sources = sources
	shadow.size_scale = p_size_scale
	shadow.single_layer = p_single_layer
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
	var host_node := _host as Node2D
	var centre: Vector2 = host_node.global_position
	if is_instance_valid(anchor):
		centre = anchor.global_position
	# The offset is in the world frame: the light is above,
	# so the shadow always sits down-screen from the host
	# however the host itself is turned. The shadow's own
	# turn still follows the host, so a silhouette's shape
	# matches the rotated sprite.
	global_position = centre + offset_px
	global_rotation = host_node.global_rotation
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
	var grow_layers: Array = _GROW_LAYERS
	if single_layer:
		grow_layers = [_GROW_LAYERS[_GROW_LAYERS.size() - 1]]
	for grow in grow_layers:
		var layer := Node2D.new()
		add_child(layer)
		_layers.append(layer)
		for source in sources:
			var copy: CanvasItem = _make_copy(source)
			if not is_instance_valid(copy):
				continue
			if copy is Sprite2D or copy is AnimatedSprite2D:
				copy.material = _clip_material
			layer.add_child(copy)
			var base_scale: Vector2 = (copy as Node2D).scale
			var grow_info := _get_grow(
				source,
				Vector2(float(grow[0]), float(grow[1])),
			)
			var factor := grow_info[0] as Vector2
			var centre := grow_info[1] as Vector2
			# Scale about the art's own centre, so the rim
			# shows evenly on every side.
			var shift: Vector2 = (
				base_scale * ((Vector2.ONE - factor) * centre)
			)
			copy.position += Transform2D(
				copy.rotation,
				Vector2.ZERO,
			).basis_xform(shift)
			_copies.append(
				[
					copy,
					source,
					float(grow[2]),
					base_scale,
					factor,
					Vector2(float(grow[0]), float(grow[1])),
				],
			)
	_update_clip()


## The per-axis scale that grows `source`'s art by `margin`
## world pixels (x and y separately), with the art's centre in
## the source's local units. Sprite art is measured by the
## texture's used (non-transparent) rect: the art sits in a
## mostly transparent canvas, and a margin on the whole canvas
## would barely grow the art itself.
func _get_grow(source: CanvasItem, margin: Vector2) -> Array:
	var size := Vector2.ZERO
	var centre := Vector2.ZERO
	if source is Polygon2D:
		var polygon_source := source as Polygon2D
		if not polygon_source.polygon.is_empty():
			var bounds := Rect2(polygon_source.polygon[0], Vector2.ZERO)
			for point in polygon_source.polygon:
				bounds = bounds.expand(point)
			size = bounds.size
			centre = bounds.get_center() + polygon_source.offset
	elif source is AnimatedSprite2D:
		var animated_source := source as AnimatedSprite2D
		if is_instance_valid(animated_source.sprite_frames):
			var texture := animated_source.sprite_frames.get_frame_texture(
				animated_source.animation,
				animated_source.frame,
			)
			if is_instance_valid(texture):
				var used := _get_used_rect(texture)
				size = Vector2(used.size)
				var top_left := animated_source.offset + Vector2(used.position)
				if animated_source.centered:
					top_left -= texture.get_size() * 0.5
				centre = top_left + size * 0.5
	elif source is Sprite2D:
		var sprite_source := source as Sprite2D
		if is_instance_valid(sprite_source.texture):
			if sprite_source.region_enabled:
				size = sprite_source.region_rect.size
				centre = sprite_source.offset + (
					Vector2.ZERO if sprite_source.centered else size * 0.5
				)
			else:
				var used := _get_used_rect(sprite_source.texture)
				size = Vector2(used.size)
				var top_left := sprite_source.offset + Vector2(used.position)
				if sprite_source.centered:
					top_left -= sprite_source.texture.get_size() * 0.5
				centre = top_left + size * 0.5
	if size.x <= 0.0 or size.y <= 0.0:
		return [Vector2.ONE, Vector2.ZERO]
	var basis := source.get_global_transform()
	var world_size := Vector2(
		size.x * basis.x.length(),
		size.y * basis.y.length(),
	)
	var factor := Vector2(
		1.0 + 2.0 * margin.x / maxf(world_size.x, 0.001),
		1.0 + 2.0 * margin.y / maxf(world_size.y, 0.001),
	)
	return [factor, centre]


static var _used_rects: Dictionary = {}


## The used (non-transparent) rect of a texture, in texture
## pixels. Cached, since reading a texture's pixels is slow and
## the answer never changes.
func _get_used_rect(texture: Texture2D) -> Rect2i:
	if _used_rects.has(texture):
		return _used_rects[texture] as Rect2i
	var rect := Rect2i(Vector2i.ZERO, Vector2i(texture.get_size()))
	var image := texture.get_image()
	if is_instance_valid(image) and not image.is_empty():
		rect = image.get_used_rect()
	_used_rects[texture] = rect
	return rect


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


## Keeps the silhouette matched to the host: transform per grow
## layer, per-copy visibility, animation frames and darkness.
## Sprite copies also track their source's texture and region,
## so a sprite whose art is assigned after the shadow was built
## (a part's `setup()`) still casts. The grow is recomputed
## only when a tracked value actually changes.
func _sync_silhouette() -> void:
	if kind != Kind.SILHOUETTE or _copies.is_empty():
		return
	var host_transform := _host.get_global_transform()
	for layer in _layers:
		# No grow here: each copy carries its own scale factor,
		# applied around the art's centre at build time.
		layer.global_transform = Transform2D(
			host_transform.x,
			host_transform.y,
			global_position,
		)
	for pair in _copies:
		var copy := pair[0] as CanvasItem
		var source := pair[1] as CanvasItem
		if copy is Sprite2D and source is Sprite2D:
			_sync_sprite_copy(pair)
		if copy is Polygon2D and source is Polygon2D:
			var polygon_copy := copy as Polygon2D
			var polygon_source := source as Polygon2D
			if polygon_copy.polygon != polygon_source.polygon:
				polygon_copy.polygon = polygon_source.polygon
				_refresh_grow(pair)
			if polygon_copy.offset != polygon_source.offset:
				polygon_copy.offset = polygon_source.offset
				_refresh_grow(pair)
		if copy is AnimatedSprite2D and source is AnimatedSprite2D:
			var animated_copy := copy as AnimatedSprite2D
			var animated_source := source as AnimatedSprite2D
			if animated_copy.sprite_frames != animated_source.sprite_frames:
				animated_copy.sprite_frames = animated_source.sprite_frames
				_refresh_grow(pair)
			if animated_copy.centered != animated_source.centered:
				animated_copy.centered = animated_source.centered
				_refresh_grow(pair)
			if animated_copy.offset != animated_source.offset:
				animated_copy.offset = animated_source.offset
				_refresh_grow(pair)
			if animated_copy.flip_h != animated_source.flip_h:
				animated_copy.flip_h = animated_source.flip_h
			if animated_copy.flip_v != animated_source.flip_v:
				animated_copy.flip_v = animated_source.flip_v
			animated_copy.animation = animated_source.animation
			animated_copy.frame = animated_source.frame
		copy.scale = (pair[3] as Vector2) * (pair[4] as Vector2) * size_scale
		copy.visible = source.is_visible_in_tree() and _host.visible
		copy.modulate = Color(
			0.0,
			0.0,
			0.0,
			_get_alpha() * _fade * float(pair[2]),
		)


## Copies a `Sprite2D` source's art onto its shadow copy when
## it has changed, and recomputes the grow when the art's size
## or centre may have moved with it.
func _sync_sprite_copy(pair: Array) -> void:
	var sprite_copy := pair[0] as Sprite2D
	var sprite_source := pair[1] as Sprite2D
	var needs_grow := false
	if sprite_copy.texture != sprite_source.texture:
		sprite_copy.texture = sprite_source.texture
		needs_grow = true
	if sprite_copy.region_enabled != sprite_source.region_enabled:
		sprite_copy.region_enabled = sprite_source.region_enabled
		needs_grow = true
	if sprite_copy.region_rect != sprite_source.region_rect:
		sprite_copy.region_rect = sprite_source.region_rect
		needs_grow = true
	if sprite_copy.hframes != sprite_source.hframes:
		sprite_copy.hframes = sprite_source.hframes
		needs_grow = true
	if sprite_copy.vframes != sprite_source.vframes:
		sprite_copy.vframes = sprite_source.vframes
		needs_grow = true
	if sprite_copy.frame != sprite_source.frame:
		sprite_copy.frame = sprite_source.frame
	if sprite_copy.frame_coords != sprite_source.frame_coords:
		sprite_copy.frame_coords = sprite_source.frame_coords
	if sprite_copy.centered != sprite_source.centered:
		sprite_copy.centered = sprite_source.centered
		needs_grow = true
	if sprite_copy.offset != sprite_source.offset:
		sprite_copy.offset = sprite_source.offset
		needs_grow = true
	if sprite_copy.flip_h != sprite_source.flip_h:
		sprite_copy.flip_h = sprite_source.flip_h
	if sprite_copy.flip_v != sprite_source.flip_v:
		sprite_copy.flip_v = sprite_source.flip_v
	if needs_grow:
		_refresh_grow(pair)


## Recomputes a copy's grow factor and centre shift from its
## source as it stands now, and refreshes the copy's base pose
## from the source's current pose under the host. Called only
## when the source's art has changed, so the used-rect lookup
## stays rare (and cached).
func _refresh_grow(pair: Array) -> void:
	if pair.size() <= 5 or not is_instance_valid(_host):
		return
	var copy := pair[0] as Node2D
	var source := pair[1] as CanvasItem
	var margin := pair[5] as Vector2
	var grow_info := _get_grow(source, margin)
	var factor := grow_info[0] as Vector2
	var centre := grow_info[1] as Vector2
	var relative := (
		_host.get_global_transform().affine_inverse()
		* source.get_global_transform()
	)
	var base_scale := relative.get_scale()
	pair[3] = base_scale
	pair[4] = factor
	var shift := base_scale * ((Vector2.ONE - factor) * centre)
	copy.position = relative.origin + Transform2D(
		relative.get_rotation(),
		Vector2.ZERO,
	).basis_xform(shift)
	copy.rotation = relative.get_rotation()


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
