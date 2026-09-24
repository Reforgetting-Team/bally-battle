extends Node2D

const CLOUD_GAP: float = 10.0
const CLOUD_SPEED: float = 18.0
const DESIGN_WIDTH: float = 1920.0
const DESIGN_HEIGHT: float = 1080.0
const FAR_SKY_SCROLL_SCALE := Vector2(0.92, 0.96)
const MIN_CAMERA_ZOOM: float = 0.45
const COVERAGE_MULTIPLIER: float = 3.0

const COMPOSITE_TEXTURE: Texture2D = preload("res://Menu/Background.png")
const SKY_TEXTURE: Texture2D = preload("res://Areas/Background.png")
const TERRAIN_TEXTURE: Texture2D = preload("res://Areas/Terrain.png")
const CLOUD_TEXTURE: Texture2D = preload("res://Areas/Clouds.png")
const LEFT_BOTTOM_CLOUD_TEXTURE: Texture2D = preload("res://Areas/LeftBottomCloud.png")
const RIGHT_BOTTOM_CLOUD_TEXTURE: Texture2D = preload("res://Areas/RightBottomCloud.png")

var far_sky_parallax: Parallax2D
var far_sky_layer: CanvasLayer
var top_cloud_layer: CanvasLayer
var far_sky_container: Control
var sky_rect: TextureRect
var background_rect: TextureRect
var bottom_layer: CanvasLayer
var bottom_container: Control
var terrain_rect: TextureRect
var left_bottom_cloud_rect: TextureRect
var right_bottom_cloud_rect: TextureRect
var cloud_container: Control
var cloud_atlas: AtlasTexture
var composite_bottom_atlas: AtlasTexture
var terrain_atlas: AtlasTexture
var left_cloud_atlas: AtlasTexture
var right_cloud_atlas: AtlasTexture
var cloud_rects: Array[TextureRect] = []
var cloud_scroll_x: float = 0.0
var cloud_step: float = 0.0

func _ready() -> void:
	z_as_relative = false

	far_sky_layer = CanvasLayer.new()
	far_sky_layer.name = "FarSkyLayer"
	far_sky_layer.layer = -3
	add_child(far_sky_layer)

	far_sky_parallax = Parallax2D.new()
	far_sky_parallax.name = "FarSkyParallax"
	far_sky_parallax.scroll_scale = FAR_SKY_SCROLL_SCALE
	far_sky_layer.add_child(far_sky_parallax)

	far_sky_container = Control.new()
	far_sky_container.name = "FarSkyContainer"
	far_sky_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	far_sky_parallax.add_child(far_sky_container)

	sky_rect = TextureRect.new()
	sky_rect.name = "SkyRect"
	sky_rect.texture = SKY_TEXTURE
	sky_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky_rect.stretch_mode = TextureRect.STRETCH_TILE
	sky_rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	far_sky_container.add_child(sky_rect)

	background_rect = TextureRect.new()
	background_rect.name = "BackgroundRect"
	background_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	far_sky_container.add_child(background_rect)

	top_cloud_layer = CanvasLayer.new()
	top_cloud_layer.name = "TopCloudLayer"
	top_cloud_layer.layer = -2
	add_child(top_cloud_layer)

	cloud_container = Control.new()
	cloud_container.name = "TopCloudsContainer"
	cloud_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_cloud_layer.add_child(cloud_container)

	bottom_layer = CanvasLayer.new()
	bottom_layer.name = "ScreenSpaceBottomLayer"
	bottom_layer.layer = -1
	add_child(bottom_layer)

	bottom_container = Control.new()
	bottom_container.name = "BottomComposition"
	bottom_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_layer.add_child(bottom_container)

	composite_bottom_atlas = AtlasTexture.new()
	composite_bottom_atlas.atlas = COMPOSITE_TEXTURE
	composite_bottom_atlas.region = Rect2(0, 0, DESIGN_WIDTH, DESIGN_HEIGHT)

	terrain_atlas = AtlasTexture.new()
	terrain_atlas.atlas = TERRAIN_TEXTURE
	terrain_atlas.region = Rect2(285, 959, 1243, 121)
	terrain_rect = _create_texture_rect("TerrainOverlay", terrain_atlas, bottom_container)

	left_cloud_atlas = AtlasTexture.new()
	left_cloud_atlas.atlas = LEFT_BOTTOM_CLOUD_TEXTURE
	left_cloud_atlas.region = Rect2(0, 747, 342, 333)
	left_bottom_cloud_rect = _create_texture_rect("LeftBottomCloud", left_cloud_atlas, bottom_container)

	right_cloud_atlas = AtlasTexture.new()
	right_cloud_atlas.atlas = RIGHT_BOTTOM_CLOUD_TEXTURE
	right_cloud_atlas.region = Rect2(1493, 804, 427, 276)
	right_bottom_cloud_rect = _create_texture_rect("RightBottomCloud", right_cloud_atlas, bottom_container)

	cloud_atlas = AtlasTexture.new()
	cloud_atlas.atlas = CLOUD_TEXTURE
	cloud_atlas.region = Rect2(18, 10, 1902, 299)

	_update_layout()
	get_viewport().size_changed.connect(_update_layout)

func _process(delta: float) -> void:
	if cloud_step <= 0.0:
		return
	cloud_scroll_x = fmod(cloud_scroll_x + CLOUD_SPEED * delta, cloud_step)
	_update_cloud_positions()

func _create_texture_rect(node_name: String, texture: Texture2D, parent: Node) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

func _update_layout() -> void:
	if not is_inside_tree():
		return

	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var scale_factor := viewport_size.y / DESIGN_HEIGHT
	var design_width_scaled := DESIGN_WIDTH * scale_factor
	var is_standard_16_9: bool = absf(viewport_size.x - design_width_scaled) <= 2.0
	var coverage_size := viewport_size / MIN_CAMERA_ZOOM * COVERAGE_MULTIPLIER
	var coverage_position := -coverage_size * 0.5

	far_sky_container.position = coverage_position
	far_sky_container.size = coverage_size
	sky_rect.position = Vector2.ZERO
	sky_rect.size = coverage_size

	if is_standard_16_9:
		background_rect.texture = COMPOSITE_TEXTURE
		background_rect.stretch_mode = TextureRect.STRETCH_SCALE
		background_rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		background_rect.position = Vector2.ZERO
		background_rect.size = coverage_size
	else:
		background_rect.texture = SKY_TEXTURE
		background_rect.stretch_mode = TextureRect.STRETCH_TILE
		background_rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		background_rect.position = Vector2.ZERO
		background_rect.size = coverage_size

	bottom_container.position = Vector2.ZERO
	bottom_container.size = viewport_size
	terrain_rect.visible = true
	left_bottom_cloud_rect.visible = not is_standard_16_9
	right_bottom_cloud_rect.visible = not is_standard_16_9

	if is_standard_16_9:
		# The 16:9 source is transparent above its baked bottom artwork. Draw the
		# complete image in screen space so that artwork stays aligned exactly as authored.
		terrain_rect.texture = composite_bottom_atlas
		terrain_rect.size = Vector2(design_width_scaled, viewport_size.y)
		terrain_rect.position = Vector2((viewport_size.x - design_width_scaled) * 0.5, 0.0)
	else:
		terrain_rect.texture = terrain_atlas
		var terrain_size := terrain_atlas.region.size * scale_factor
		terrain_rect.size = terrain_size
		terrain_rect.position = Vector2((viewport_size.x - terrain_size.x) * 0.5, viewport_size.y - terrain_size.y)

	var left_cloud_size := left_cloud_atlas.region.size * scale_factor
	left_bottom_cloud_rect.size = left_cloud_size
	left_bottom_cloud_rect.position = Vector2(0.0, viewport_size.y - left_cloud_size.y)

	var right_cloud_size := right_cloud_atlas.region.size * scale_factor
	right_bottom_cloud_rect.size = right_cloud_size
	right_bottom_cloud_rect.position = Vector2(viewport_size.x - right_cloud_size.x, viewport_size.y - right_cloud_size.y)

	cloud_container.position = Vector2(-coverage_size.x * 0.5, 0.0)
	cloud_container.size = coverage_size
	_rebuild_top_clouds(coverage_size, scale_factor)

func _rebuild_top_clouds(coverage_size: Vector2, scale_factor: float) -> void:
	for child in cloud_container.get_children():
		child.queue_free()
	cloud_rects.clear()

	var cloud_size := cloud_atlas.region.size * scale_factor
	cloud_step = cloud_size.x + CLOUD_GAP
	if cloud_step <= 0.0:
		return

	var needed_count := int(ceil(coverage_size.x / cloud_step)) + 2
	for i in range(needed_count):
		var cloud := _create_texture_rect("Cloud%d" % (i + 1), cloud_atlas, cloud_container)
		cloud.size = cloud_size
		cloud_rects.append(cloud)
	_update_cloud_positions()

func _update_cloud_positions() -> void:
	var base_x := cloud_scroll_x - cloud_step
	for i in range(cloud_rects.size()):
		if is_instance_valid(cloud_rects[i]):
			cloud_rects[i].position = Vector2(base_x + i * cloud_step, 0.0)
