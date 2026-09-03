@tool
extends CanvasLayer

# Global Persistent Background System:
# - Autoloaded as "Background" so clouds NEVER reset when transitioning between menus or maps
# - 16:9 resolutions: Displays the original full Background illustration with drifting top clouds
# - Ultrawide / non-16:9: Displays tiled Background.png, centered Terrain, pinned bottom corner clouds, and drifting top clouds

const CLOUD_GAP: float = 10.0
const DESIGN_WIDTH: float = 1920.0
const DESIGN_HEIGHT: float = 1080.0

@export var cloud_scroll_speed: float = 18.0 # pixels per second

@onready var bg_rect: TextureRect = $BackgroundRect
@onready var terrain_rect: TextureRect = $TerrainRect
@onready var left_cloud_rect: TextureRect = $LeftBottomCloudRect
@onready var right_cloud_rect: TextureRect = $RightBottomCloudRect
@onready var top_clouds_container: Control = $TopCloudsContainer

var composite_bg_texture: Texture2D = preload("res://Menu/Background.png")
var tiled_bg_texture: Texture2D = preload("res://Areas/Background.png")
var clouds_texture: Texture2D = preload("res://Areas/Clouds.png")
var terrain_texture: Texture2D = preload("res://Areas/Terrain.png")
var left_cloud_texture: Texture2D = preload("res://Areas/LeftBottomCloud.png")
var right_cloud_texture: Texture2D = preload("res://Areas/RightBottomCloud.png")

var clouds_atlas: AtlasTexture
var terrain_atlas: AtlasTexture
var left_cloud_atlas: AtlasTexture
var right_cloud_atlas: AtlasTexture

var _cloud_scroll_x: float = 0.0
var _active_cloud_nodes: Array[TextureRect] = []

func _ready() -> void:
	layer = -100 # Always render behind all menus, UI, ground tiles, and players
	_setup_textures()
	_update_layout()
	get_viewport().size_changed.connect(_update_layout)

func _setup_textures() -> void:
	clouds_atlas = AtlasTexture.new()
	clouds_atlas.atlas = clouds_texture
	clouds_atlas.region = Rect2(18, 10, 1902, 299)

	terrain_atlas = AtlasTexture.new()
	terrain_atlas.atlas = terrain_texture
	terrain_atlas.region = Rect2(285, 959, 1243, 121)

	left_cloud_atlas = AtlasTexture.new()
	left_cloud_atlas.atlas = left_cloud_texture
	left_cloud_atlas.region = Rect2(0, 747, 342, 333)

	right_cloud_atlas = AtlasTexture.new()
	right_cloud_atlas.atlas = right_cloud_texture
	right_cloud_atlas.region = Rect2(1493, 804, 427, 276)

	if terrain_rect:
		terrain_rect.texture = terrain_atlas
		terrain_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if left_cloud_rect:
		left_cloud_rect.texture = left_cloud_atlas
		left_cloud_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if right_cloud_rect:
		right_cloud_rect.texture = right_cloud_atlas
		right_cloud_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if bg_rect:
		bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

func _process(delta: float) -> void:
	if not clouds_atlas:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		vp_size = Vector2(1152, 648)
	var scale_factor: float = vp_size.y / DESIGN_HEIGHT
	var cloud_width: float = clouds_atlas.region.size.x * scale_factor
	var step_x: float = cloud_width + CLOUD_GAP
	if step_x <= 0.0:
		return

	# Persistent cloud drift (never resets on scene changes)
	_cloud_scroll_x += cloud_scroll_speed * delta
	if _cloud_scroll_x >= step_x:
		_cloud_scroll_x = fmod(_cloud_scroll_x, step_x)

	_update_cloud_positions(step_x)

func _update_layout() -> void:
	if not is_inside_tree():
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		vp_size = Vector2(1152, 648)

	var scale_factor: float = vp_size.y / DESIGN_HEIGHT
	var design_w_scaled: float = DESIGN_WIDTH * scale_factor
	var is_standard_16_9: bool = vp_size.x <= design_w_scaled + 2.0

	if is_standard_16_9:
		# Standard 16:9: Use the original full 16:9 illustration (Menu/Background.png)
		if bg_rect:
			bg_rect.texture = composite_bg_texture
			bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
			bg_rect.size = Vector2(design_w_scaled, vp_size.y)
			bg_rect.position = Vector2((vp_size.x - design_w_scaled) * 0.5, 0.0)

		# Hide individual pieces since they are already in the 16:9 composite artwork
		if terrain_rect:
			terrain_rect.visible = false
		if left_cloud_rect:
			left_cloud_rect.visible = false
		if right_cloud_rect:
			right_cloud_rect.visible = false
	else:
		# Ultrawide (>16:9): Tile background and anchor separate corner clouds and terrain
		if bg_rect:
			bg_rect.texture = tiled_bg_texture
			bg_rect.stretch_mode = TextureRect.STRETCH_TILE
			bg_rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			bg_rect.size = vp_size
			bg_rect.position = Vector2.ZERO

		if terrain_rect and terrain_atlas:
			terrain_rect.visible = true
			var t_size := terrain_atlas.region.size * scale_factor
			terrain_rect.size = t_size
			terrain_rect.position = Vector2((vp_size.x - t_size.x) * 0.5, vp_size.y - t_size.y)

		if left_cloud_rect and left_cloud_atlas:
			left_cloud_rect.visible = true
			var lc_size := left_cloud_atlas.region.size * scale_factor
			left_cloud_rect.size = lc_size
			left_cloud_rect.position = Vector2(0.0, vp_size.y - lc_size.y)

		if right_cloud_rect and right_cloud_atlas:
			right_cloud_rect.visible = true
			var rc_size := right_cloud_atlas.region.size * scale_factor
			right_cloud_rect.size = rc_size
			right_cloud_rect.position = Vector2(vp_size.x - rc_size.x, vp_size.y - rc_size.y)

	# Build top drifting clouds across full width
	_rebuild_top_clouds(vp_size, scale_factor)

func _rebuild_top_clouds(vp_size: Vector2, scale_factor: float) -> void:
	if not top_clouds_container or not clouds_atlas:
		return

	for child in top_clouds_container.get_children():
		child.queue_free()
	_active_cloud_nodes.clear()

	var cloud_size := clouds_atlas.region.size * scale_factor
	var step_x := cloud_size.x + CLOUD_GAP
	if step_x <= 0.0:
		return

	var needed_count := int(ceil(vp_size.x / step_x)) + 2
	for i in range(needed_count):
		var cloud := TextureRect.new()
		cloud.texture = clouds_atlas
		cloud.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cloud.size = cloud_size
		top_clouds_container.add_child(cloud)
		_active_cloud_nodes.append(cloud)

	_update_cloud_positions(step_x)

func _update_cloud_positions(step_x: float) -> void:
	var base_x := _cloud_scroll_x - step_x
	for i in range(_active_cloud_nodes.size()):
		var cloud := _active_cloud_nodes[i]
		if is_instance_valid(cloud):
			cloud.position = Vector2(base_x + i * step_x, 0.0)
