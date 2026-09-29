extends Camera2D

# so ts keeps the whole fight on screen like bopl, then eases in when everyones close

@export var min_zoom_scale: float = 0.45
@export var max_zoom_scale: float = 0.85
@export var edge_padding: float = 150.0
@export var vertical_bias: float = -24.0
@export var pan_speed: float = 7.0
@export var zoom_speed: float = 4.0

var _current_zoom_scalar: float = 1.0
var _camera_initialized: bool = false
var _shake_strength: float = 0.0
var _shake_time_left: float = 0.0
var _shake_duration: float = 0.0

func _ready() -> void:
	_current_zoom_scalar = max_zoom_scale
	zoom = Vector2(_current_zoom_scalar, _current_zoom_scalar)
	make_current()

func shake(strength: float, duration: float) -> void:
	# stack nearby booms so they hit harder without making the camera drift
	_shake_strength = max(_shake_strength, strength)
	_shake_time_left = max(_shake_time_left, duration)
	_shake_duration = max(_shake_duration, duration)

func _physics_process(delta: float) -> void:
	var players: Array = []
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and not p.is_queued_for_deletion() and not ("is_dead" in p and p.is_dead):
			players.append(p)

	if players.is_empty():
		_update_shake(delta)
		return

	# bounding box of every living player right now
	var min_pos: Vector2 = players[0].global_position
	var max_pos: Vector2 = players[0].global_position
	for p in players:
		var pos: Vector2 = p.global_position
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.y = min(min_pos.y, pos.y)
		max_pos.x = max(max_pos.x, pos.x)
		max_pos.y = max(max_pos.y, pos.y)

	var center: Vector2 = (min_pos + max_pos) * 0.5
	center.y += vertical_bias
	var spread: Vector2 = max_pos - min_pos
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return

	# use the real viewport so ultrawide and resized windows frame the same way
	var needed_zoom_x: float = view_size.x / (spread.x + edge_padding * 2.0)
	var needed_zoom_y: float = view_size.y / (spread.y + edge_padding * 2.0)
	var target_zoom_scalar: float = clamp(min(needed_zoom_x, needed_zoom_y), min_zoom_scale, max_zoom_scale)

	# exponential easing feels the same at 30fps and 144fps
	var pan_weight: float = 1.0 - exp(-pan_speed * delta)
	var zoom_weight: float = 1.0 - exp(-zoom_speed * delta)
	if not _camera_initialized:
		global_position = center
		_current_zoom_scalar = target_zoom_scalar
		_camera_initialized = true
	else:
		global_position = global_position.lerp(center, pan_weight)
		_current_zoom_scalar = lerp(_current_zoom_scalar, target_zoom_scalar, zoom_weight)
	zoom = Vector2(_current_zoom_scalar, _current_zoom_scalar)
	_update_shake(delta)

func _update_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		# boom's over, clear the values so future small shakes dont stay huge forever lol
		_shake_strength = 0.0
		_shake_duration = 0.0
		offset = Vector2.ZERO
		return

	_shake_time_left = max(_shake_time_left - delta, 0.0)
	var fade: float = _shake_time_left / max(_shake_duration, 0.001)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * fade
	if _shake_time_left <= 0.0:
		_shake_strength = 0.0
		_shake_duration = 0.0
		offset = Vector2.ZERO
