extends "res://Areas/Player.gd"

# so ts gives the tutorial a lil target that comes back after every bonk
@export_range(0.0, 5.0, 0.1) var respawn_delay: float = 0.6

var _home_position: Vector2 = Vector2.ZERO
var _home_rotation: float = 0.0
var _home_sprite_rotation: float = 0.0
var _home_collision_layer: int = 0
var _home_collision_mask: int = 0

func _ready() -> void:
	is_tutorial_dummy = true
	# path-based IDs stay unique when u duplicate a dummy in the tutorial
	player_id = -1000 - posmod(str(get_path()).hash(), 1000000000)
	_home_position = position
	_home_rotation = rotation
	_home_collision_layer = collision_layer
	_home_collision_mask = collision_mask
	if sprite:
		_home_sprite_rotation = sprite.rotation
	super._ready()

func _physics_process(delta: float) -> void:
	if is_dead or NetworkManagerScript.is_scene_transitioning:
		return
	# no buttons or AI here, it just falls n gets launched like a lil target
	if not is_on_floor():
		velocity += get_gravity() * delta
		velocity.x = move_toward(velocity.x, 0.0, air_friction * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	move_and_slide()
	if sprite:
		sprite.rotation += (velocity.x * delta) / ball_radius

func die() -> void:
	if is_dead:
		return
	# practice deaths stay local, even if somebody opens the tutorial online
	_finish_death()

func apply_blast_knockback(blast_position: Vector2, knockback_radius: float, force: float) -> void:
	if is_dead or knockback_radius <= 0.0:
		return
	var away_from_blast := global_position - blast_position
	var distance: float = away_from_blast.length()
	if distance >= knockback_radius:
		return
	if distance <= 0.001:
		away_from_blast = Vector2.UP
	var falloff: float = 1.0 - distance / knockback_radius
	var knockback_direction := away_from_blast.normalized()
	knockback_direction.y = min(knockback_direction.y, -0.55)
	velocity += knockback_direction.normalized() * force * falloff

func _on_death_cleanup_complete() -> void:
	if respawn_delay <= 0.0:
		_respawn()
		return
	get_tree().create_timer(respawn_delay).timeout.connect(_respawn, CONNECT_ONE_SHOT)

func _respawn() -> void:
	if not is_inside_tree():
		return
	position = _home_position
	rotation = _home_rotation
	velocity = Vector2.ZERO
	collision_layer = _home_collision_layer
	collision_mask = _home_collision_mask
	is_dead = false
	is_dashing = false
	dash_time_remaining = 0.0
	dash_cooldown_timer = 0.0
	is_spiky = false
	spiky_time_remaining = 0.0
	spiky_cooldown_timer = 0.0
	is_holding_bomb = false
	bomb_hold_timer = 0.0
	bomb_startup_frames_remaining = 0
	bomb_cooldown_timer = 0.0
	bounce_volume_db = 0.0
	_net_initialized = false
	_spawn_grace_frames = 30
	_hide_bomb_hold_visual()
	if sprite:
		sprite.visible = true
		sprite.rotation = _home_sprite_rotation
		sprite.modulate = Color.WHITE
	if shader_mat:
		shader_mat.set_shader_parameter("skin_color", player_color)
	if name_label:
		name_label.text = player_display_name
		name_label.visible = true
		name_label.scale = Vector2.ONE
	if spike_hitbox:
		spike_hitbox.monitoring = false
	if spikes_visual:
		spikes_visual.visible = false
		if spikes_visual.has_method("retract_spikes"):
			spikes_visual.retract_spikes()
	if wind_trail and wind_trail.has_method("stop_trail"):
		wind_trail.stop_trail()
	if death_audio and death_audio.playing:
		death_audio.stop()
	set_physics_process(true)
	_play_spawn_animation()
