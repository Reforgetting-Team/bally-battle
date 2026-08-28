extends CharacterBody2D

# player ball script with all the juicy physics, rolling, bouncing and controls

@export var speed: float = 380.0
@export var acceleration: float = 900.0
@export var friction: float = 400.0
@export var air_friction: float = 120.0
@export var jump_velocity: float = -420.0
@export var bounce_factor: float = 0.55
@export var min_bounce_speed: float = 80.0
@export var ball_radius: float = 36.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel

# sound players for jump and bounce
@onready var jump_audio: AudioStreamPlayer = $JumpAudio
@onready var bounce_audio: AudioStreamPlayer = $BounceAudio

@export var player_id: int = 1
@export var player_color: Color = Color.WHITE
@export var player_display_name: String = "Player"

var is_local_player: bool = true
var previous_velocity: Vector2 = Vector2.ZERO
var shader_mat: ShaderMaterial

# each bounce fades the sound out so it gets quieter and quieter
var bounce_volume_db: float = 0.0
const BOUNCE_FADE_DB: float = 6.0     # how many dB quieter each bounce gets
const BOUNCE_MIN_DB: float = -40.0    # silent enough to stop playing

func _ready() -> void:
	# figure out if this ball belongs to us or someone else online
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		is_local_player = (player_id == multiplayer.get_unique_id())
		set_multiplayer_authority(player_id)
	else:
		is_local_player = true
		player_color = PlayerData.skin_color
		player_display_name = PlayerData.player_name

	# slap the recolor shader on the ball so the color actually shows up
	if sprite:
		var shader = load("res://Character/recolor.gdshader") as Shader
		shader_mat = ShaderMaterial.new()
		shader_mat.shader = shader
		shader_mat.set_shader_parameter("skin_color", player_color)
		sprite.material = shader_mat

	# show the gamer tag above the ball
	if name_label:
		name_label.text = player_display_name

	# slope physics tweaking so we slide down hills like a real ball
	floor_stop_on_slope = false
	floor_constant_speed = false
	floor_max_angle = deg_to_rad(65.0)
	floor_snap_length = 12.0

func setup_player(id: int, p_name: String, color: Color) -> void:
	player_id = id
	player_display_name = p_name
	player_color = color

	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		is_local_player = (player_id == multiplayer.get_unique_id())
		set_multiplayer_authority(player_id)

	if shader_mat:
		shader_mat.set_shader_parameter("skin_color", player_color)

	if name_label:
		name_label.text = player_display_name

func _physics_process(delta: float) -> void:
	# if this aint our ball, let the network sync move it instead
	if not is_local_player:
		return

	var gravity = get_gravity()

	# falling and slope sliding stuff
	if not is_on_floor():
		velocity += gravity * delta
	else:
		# roll down slopes naturally
		var floor_normal = get_floor_normal()
		if floor_normal != Vector2.UP and floor_normal != Vector2.ZERO:
			var slope_tangent = Vector2(floor_normal.y, -floor_normal.x)
			var slope_pull = gravity.dot(slope_tangent)
			velocity += slope_tangent * slope_pull * delta * 0.85

	# input handling: wasd / arrows or hold left click to steer
	var input_x: float = 0.0

	# 1. keyboard / dpad
	input_x = Input.get_axis("ui_left", "ui_right")
	if input_x == 0.0:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			input_x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			input_x += 1.0

	# 2. mouse steer - hold left click and ball rolls towards your cursor
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse_pos = get_global_mouse_position()
		var diff_x = mouse_pos.x - global_position.x
		if abs(diff_x) > 16.0:
			input_x = clamp(diff_x / 100.0, -1.0, 1.0)

	# speed up or coast smoothly with inertia so it rolls a bit further
	var current_friction = friction if is_on_floor() else air_friction
	if abs(input_x) > 0.05:
		velocity.x = move_toward(velocity.x, input_x * speed, acceleration * delta)
	else:
		# coasting to a stop
		velocity.x = move_toward(velocity.x, 0.0, current_friction * delta)

	# jump with space / w / up arrow
	var jump_pressed = Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP)
	if jump_pressed and is_on_floor():
		velocity.y = jump_velocity
		# play the pop sound and reset bounce volume for next landing
		bounce_volume_db = 0.0
		_play_jump_sound()

	# remember speed before collision so we can do sick bounces
	var pre_move_vel = velocity

	# move the body
	move_and_slide()

	# check if jump is held down so we can chain jumps on bounce
	var jump_held = Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP)

	# ball bounce restitution: hit the ground and boing with fading volume each hop
	if is_on_floor() and pre_move_vel.y > min_bounce_speed:
		if jump_held:
			# holding jump while landing? skip the bounce and just jump again
			velocity.y = jump_velocity
			bounce_volume_db = 0.0
			_play_jump_sound()
		else:
			velocity.y = -pre_move_vel.y * bounce_factor
			_play_bounce_sound()
	elif is_on_ceiling() and pre_move_vel.y < -min_bounce_speed:
		velocity.y = -pre_move_vel.y * bounce_factor
		_play_bounce_sound()

	# bounce off walls if we slam into them fast enough
	if is_on_wall() and abs(pre_move_vel.x) > min_bounce_speed:
		velocity.x = -pre_move_vel.x * (bounce_factor * 0.75)

	# make the ball sprite actually roll and spin while moving
	if sprite:
		sprite.rotation += (velocity.x * delta) / ball_radius

	# spam our position to other players so they see us rolling
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		_sync_transform.rpc(global_position, sprite.rotation if sprite else 0.0, velocity)

func _play_jump_sound() -> void:
	if jump_audio and jump_audio.stream:
		jump_audio.volume_db = 0.0
		jump_audio.play()

func _play_bounce_sound() -> void:
	# each bounce gets quieter until its basically silent
	if bounce_volume_db <= BOUNCE_MIN_DB:
		return
	if bounce_audio and bounce_audio.stream:
		bounce_audio.volume_db = bounce_volume_db
		bounce_audio.play()
	bounce_volume_db -= BOUNCE_FADE_DB

@rpc("unreliable")
func _sync_transform(pos: Vector2, rot: float, vel: Vector2) -> void:
	if is_local_player:
		return
	global_position = pos
	velocity = vel
	if sprite:
		sprite.rotation = rot
