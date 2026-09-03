extends CharacterBody2D

# player ball script with all the juicy physics, rolling, bouncing and controls

@export var speed: float = 380.0
@export var acceleration: float = 900.0
@export var friction: float = 400.0
@export var air_friction: float = 120.0
@export var jump_velocity: float = -500.0
@export var bounce_factor: float = 0.55
@export var min_bounce_speed: float = 80.0
@export var ball_radius: float = 36.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel

# sound players for jump/bounce (shared, so they can never overlap - see
# _play_impact_sound below) and death
@onready var impact_audio: AudioStreamPlayer = $ImpactAudio
@onready var death_audio: AudioStreamPlayer = $DeathAudio
@onready var dash_audio: AudioStreamPlayer = get_node_or_null("DashAudio")
@onready var wind_trail: Node2D = get_node_or_null("WindTrail")
@onready var spikes_visual: Node2D = get_node_or_null("SpikesVisual")
@onready var spike_hitbox: Area2D = get_node_or_null("SpikeHitbox")

const JUMP_STREAM: AudioStream = preload("res://Sounds/Pop.ogg")
const BOUNCE_STREAM: AudioStream = preload("res://Sounds/Tongue.ogg")
const WindShader: Shader = preload("res://Character/wind_trail.gdshader")

# TEMP debug instrumentation to trace exactly when/why sounds fire
var _sound_debug_log: Array = []


@export var player_id: int = 1
@export var player_color: Color = Color.WHITE
@export var player_display_name: String = "Player"

signal player_died(player_id: int)

# Abilities / Powers system - you zoom fast as heck and pop spikes
var equipped_powers: Array = ["dash"]
var is_dashing: bool = false
var dash_cooldown_timer: float = 0.0
var dash_time_remaining: float = 0.0
const DASH_COOLDOWN: float = 1.2
const DASH_DURATION: float = 0.22 # gives you that nice beefy burst duration
const DASH_SPEED: float = 950.0
var dash_direction: float = 1.0
var last_move_dir_x: float = 1.0

# Spiky power - grow sharp triangles that eliminate anyone you bump into
var is_spiky: bool = false
var spiky_time_remaining: float = 0.0
var spiky_cooldown_timer: float = 0.0
const SPIKY_DURATION: float = 3.5
const SPIKY_COOLDOWN: float = 4.5

var is_local_player: bool = true
var previous_velocity: Vector2 = Vector2.ZERO
var shader_mat: ShaderMaterial
var sprite_base_scale: Vector2 = Vector2.ONE

# right after spawning, the very first physics frames can report a
# floor_normal that's ever so slightly off from a perfectly flat (0,-1)
# before collision fully settles - without this grace window that tiny
# wobble reads as "on a slope" and the roll-down-slopes code below shoves
# the ball sideways right out from under itself before the player even
# sees it land
var _spawn_grace_frames: int = 30

# each bounce fades the sound out so it gets quieter and quieter
var bounce_volume_db: float = 0.0
const BOUNCE_FADE_DB: float = 6.0     # how many dB quieter each bounce gets
const BOUNCE_MIN_DB: float = -40.0    # silent enough to stop playing

# death handling - starts below the corner (in the "void") and rises up into
# view using the exact same velocity/gravity/move_and_slide a normal jump
# uses, peaks in the corner spot matching the picture, then falls back down
# and out for good
var is_dead: bool = false
var death_entry_y: float = 0.0
const DEATH_SINK_MARGIN: float = 150.0 # how far past where it re-entered it has to fall before it's removed
const DEATH_RISE_MARGIN: float = 60.0  # extra distance below the screen edge so the climb into view is actually visible, not instant

const DEATH_ANCHOR_X: float = 1050.0   # base x - measured from the reference so the face reads fully
const DEATH_ANCHOR_Y: float = 570.0    # base y - measured from the reference so the face reads fully
const DEATH_STEP_X: float = 300.0      # each further simultaneous death steps this far left...
const DEATH_STEP_Y: float = 25.0       # ...and this far down, so they don't stack on each other
const DEATH_SPRITE_SCALE: float = 0.8  # dead face size, matched to the reference proportions

# shared across every player instance so simultaneous deaths space themselves
# out in the corner instead of landing on top of each other
static var dead_count: int = 0

func _ready() -> void:
	# figure out if this ball belongs to us or someone else online
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		is_local_player = (player_id == multiplayer.get_unique_id())
		set_multiplayer_authority(player_id)
	else:
		is_local_player = true
		player_color = PlayerData.skin_color
		player_display_name = PlayerData.player_name
		equipped_powers = PlayerData.equipped_powers.duplicate()

	# slap the recolor shader on the ball so the color actually shows up
	if sprite:
		sprite_base_scale = sprite.scale
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

	add_to_group("player")

	if spike_hitbox:
		spike_hitbox.body_entered.connect(_on_spike_hitbox_body_entered)

	if spikes_visual and spikes_visual.has_method("set_color"):
		spikes_visual.set_color(player_color)

func setup_player(id: int, p_name: String, color: Color, powers: Array = ["dash"]) -> void:
	player_id = id
	player_display_name = p_name
	player_color = color
	equipped_powers = powers.duplicate()

	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		is_local_player = (player_id == multiplayer.get_unique_id())
		set_multiplayer_authority(player_id)

	if shader_mat:
		shader_mat.set_shader_parameter("skin_color", player_color)

	if spikes_visual and spikes_visual.has_method("set_color"):
		spikes_visual.set_color(player_color)

	if name_label:
		name_label.text = player_display_name

func die() -> void:
	# never process a death twice for the same ball (e.g. void zone + something
	# else triggering die() in the same frame)
	if is_dead:
		return
	is_dead = true
	is_dashing = false
	if is_spiky:
		_stop_spiky()
	if wind_trail and wind_trail.has_method("stop_trail"):
		wind_trail.stop_trail()
	player_died.emit(player_id)

	# stop taking part in gameplay physics/collision entirely - the death hop
	# below is a self-contained fake-gravity animation, not real collision
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0

	# a fresh death shouldn't leak a still-playing jump/bounce sound into it
	if impact_audio and impact_audio.playing:
		impact_audio.stop()

	# swap to the sad face and blow it up to corner-avatar size
	if sprite:
		var sad_tex := load("res://Character/CharacterSad.svg") as Texture2D
		if sad_tex:
			sprite.texture = sad_tex
		sprite.rotation = 0.0
		sprite.scale = sprite_base_scale * (DEATH_SPRITE_SCALE / 0.19)

	# the gamer tag doesn't scale with the sprite, so it just floats oddly in
	# the middle of the big dead face - hide it, matching the reference look
	if name_label:
		name_label.visible = false

	# sad trombone
	if death_audio and death_audio.stream:
		death_audio.play()

	# figure out this death's spot in the corner - each simultaneous death claims
	# the next slot, stepping further left and slightly further down than the last
	var death_index := dead_count
	dead_count += 1
	var anchor_x := DEATH_ANCHOR_X - death_index * DEATH_STEP_X
	var anchor_y := DEATH_ANCHOR_Y + death_index * DEATH_STEP_Y

	# the sad-face sprite is much bigger than the ball, so hiding just its
	# CENTER below the screen isn't enough - the top of a tall sprite can
	# still poke into view immediately. Measure how tall it actually renders
	# right now (after the texture swap and scale change above) so we know
	# how far down its top edge really is
	var sprite_half_height: float = 0.0
	if sprite and sprite.texture:
		sprite_half_height = sprite.texture.get_height() * sprite.scale.y * 0.5

	# start low enough that the WHOLE sprite is below the visible area, plus
	# a little extra so there's a beat of travel before it crosses the
	# bottom edge - that's what reads as climbing out of the ground instead
	# of just popping into view
	var screen_bottom: float = get_viewport_rect().size.y
	var hidden_y: float = screen_bottom + sprite_half_height + DEATH_RISE_MARGIN
	var required_rise: float = max(hidden_y - anchor_y, 0.0)

	# solve for the launch speed that makes a normal gravity arc (same
	# gravity/move_and_slide the rest of the game uses for jumping) peak
	# exactly at the corner spot after covering that whole distance
	var gravity_y: float = get_gravity().y
	var launch_velocity_y: float = -sqrt(2.0 * gravity_y * required_rise) if gravity_y > 0.0 else jump_velocity

	death_entry_y = anchor_y + required_rise
	global_position = Vector2(anchor_x, death_entry_y)

	# launch upward at that solved speed - every frame from here on out uses
	# the exact same gravity + move_and_slide() as a normal jump too, see
	# _death_physics_process below, so it decelerates and settles into the
	# corner just like landing a jump
	velocity = Vector2(0.0, launch_velocity_y)

func _physics_process(delta: float) -> void:
	# dead balls run their own tiny gravity sim instead of the normal movement code
	if is_dead:
		_death_physics_process(delta)
		return

	# if this aint our ball, let the network sync move it instead
	if not is_local_player:
		return

	var gravity = get_gravity()

	# snapshot whether jump is being held ONCE per frame, right up front.
	var jump_held: bool = Input.is_action_pressed("jump") or Input.is_action_pressed("ui_accept")

	# falling and slope sliding stuff
	if not is_on_floor():
		velocity += gravity * delta
	else:
		# roll down slopes naturally
		if _spawn_grace_frames > 0:
			_spawn_grace_frames -= 1
		else:
			var floor_normal = get_floor_normal()
			# use a tolerance instead of exact equality - physics-computed
			# normals are almost never bit-exact (0,-1) even on perfectly
			# flat ground, so an exact != comparison misreads flat floors
			# as slopes and adds a tiny sideways push each frame. Harmless
			# on one big continuous floor where it's imperceptible, but on
			# a narrow floating platform it slowly rolls the ball right
			# off the edge
			if floor_normal != Vector2.ZERO and floor_normal.dot(Vector2.UP) < 0.999:
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

	# when spiky is popped, manual steering is locked! momentum just rolls naturally
	if is_spiky:
		input_x = 0.0

	# speed up or coast smoothly with inertia so it rolls a bit further
	var current_friction = friction if is_on_floor() else air_friction
	if abs(input_x) > 0.05:
		velocity.x = move_toward(velocity.x, input_x * speed, acceleration * delta)
		last_move_dir_x = sign(input_x)
	else:
		# coasting to a stop
		velocity.x = move_toward(velocity.x, 0.0, current_friction * delta)

	# dash cooldown and input handling
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = max(dash_cooldown_timer - delta, 0.0)

	if Input.is_action_just_pressed("dash"):
		_try_dash(input_x)

	if is_dashing:
		dash_time_remaining -= delta
		velocity.x = dash_direction * DASH_SPEED
		velocity.y = min(velocity.y, 0.0)
		if dash_time_remaining <= 0.0:
			_stop_dash()

	# spiky ability timer and trigger
	if spiky_cooldown_timer > 0.0:
		spiky_cooldown_timer = max(spiky_cooldown_timer - delta, 0.0)

	if Input.is_action_just_pressed("spiky"):
		_try_spiky()

	if is_spiky:
		spiky_time_remaining -= delta
		if spiky_time_remaining <= 0.0:
			_stop_spiky()

	# jump with space / w / up arrow (edge-triggered so holding it doesn't spam-jump)
	var jump_pressed = Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept")
	if jump_pressed and is_on_floor():
		velocity.y = jump_velocity
		# play the pop sound and reset bounce volume for next landing
		bounce_volume_db = 0.0
		_play_jump_sound()

	# remember speed before collision so we can do sick bounces
	var pre_move_vel = velocity

	# move the body
	move_and_slide()

	# ball bounce restitution: hit the ground and boing with fading volume each hop.
	# uses the SAME jump_held snapshot taken at the top of this frame - no second read.
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
		if spikes_visual:
			spikes_visual.rotation = sprite.rotation

	# spam our position to other players so they see us rolling
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		_sync_transform.rpc(global_position, sprite.rotation if sprite else 0.0, velocity)

func _death_physics_process(delta: float) -> void:
	# identical integration to a normal jump: accumulate gravity into velocity,
	# then move_and_slide() - same property, same call, same order of operations.
	# collision is off (layer/mask 0) so nothing blocks it, it just arcs freely.
	velocity += get_gravity() * delta
	move_and_slide()

	# it's falling back down (not still rising) and has sunk well past where it
	# re-entered - it's gone into the void for good, so remove it from the scene
	if velocity.y > 0.0 and global_position.y >= death_entry_y + DEATH_SINK_MARGIN:
		queue_free()

func _play_jump_sound() -> void:
	if impact_audio:
		impact_audio.stream = JUMP_STREAM
		impact_audio.pitch_scale = 1.0
		impact_audio.volume_db = 0.0
		impact_audio.play()
	_sound_debug_log.append({"t": Time.get_ticks_msec(), "kind": "jump"})

func _play_bounce_sound() -> void:
	if bounce_volume_db <= BOUNCE_MIN_DB:
		return
	if impact_audio:
		impact_audio.stream = BOUNCE_STREAM
		impact_audio.pitch_scale = 1.0
		impact_audio.volume_db = bounce_volume_db
		impact_audio.play()
	bounce_volume_db -= BOUNCE_FADE_DB
	_sound_debug_log.append({"t": Time.get_ticks_msec(), "kind": "bounce"})

@rpc("unreliable")
func _sync_transform(pos: Vector2, rot: float, vel: Vector2) -> void:
	if is_local_player:
		return
	global_position = pos
	velocity = vel
	if sprite:
		sprite.rotation = rot

func _try_dash(input_x: float) -> void:
	# bro pressed dash, check if we're allowed to send it
	if not equipped_powers.has("dash"):
		return
	if dash_cooldown_timer > 0.0 or is_dead:
		return

	# figure out which way to blast
	var dir: float = sign(input_x)
	if dir == 0.0:
		dir = last_move_dir_x if last_move_dir_x != 0.0 else 1.0

	_start_dash(dir)

	# tell the lobby boys we just dashed so they see our wind trail
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		_sync_dash.rpc(dash_direction)

@rpc("unreliable")
func _sync_dash(dir: float) -> void:
	# other player dashed, fire off the visual effects on our screen
	if is_local_player:
		return
	_start_dash(dir)

func _start_dash(dir: float) -> void:
	# blast off with speed lines trailing behind
	dash_direction = dir
	is_dashing = true
	dash_time_remaining = DASH_DURATION
	dash_cooldown_timer = DASH_COOLDOWN

	velocity.x = dash_direction * DASH_SPEED
	velocity.y = min(velocity.y, -80.0)

	if wind_trail and wind_trail.has_method("start_trail"):
		wind_trail.start_trail(self)
	_play_dash_sound()

func _stop_dash() -> void:
	# dash impulse done, fade out the trail smoothly
	is_dashing = false
	if wind_trail and wind_trail.has_method("stop_trail"):
		wind_trail.stop_trail()

func _play_dash_sound() -> void:
	# high pitched pop for that anime dash whoosh
	if dash_audio:
		dash_audio.play()
	elif impact_audio:
		impact_audio.stream = JUMP_STREAM
		impact_audio.pitch_scale = 1.65
		impact_audio.volume_db = 2.0
		impact_audio.play()

func _on_spike_hitbox_body_entered(body: Node2D) -> void:
	# spiky lethal touch: if we bump into an enemy player while covered in spikes, they're cooked
	if not is_spiky:
		return
	if body == self:
		return
	if body.has_method("die") and ("is_dead" in body and not body.is_dead):
		body.die()

func _try_spiky() -> void:
	# bro pressed spiky, check if equipped and ready
	if not equipped_powers.has("spiky"):
		return
	if spiky_cooldown_timer > 0.0 or is_dead or is_spiky:
		return

	_start_spiky()

	# tell everyone in the lobby we just sprouted spikes
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		_sync_spiky.rpc(true)

@rpc("unreliable")
func _sync_spiky(active: bool) -> void:
	if is_local_player:
		return
	if active:
		_start_spiky()
	else:
		_stop_spiky()

func _start_spiky() -> void:
	is_spiky = true
	spiky_time_remaining = SPIKY_DURATION
	spiky_cooldown_timer = SPIKY_COOLDOWN

	if spikes_visual and spikes_visual.has_method("pop_spikes"):
		spikes_visual.set_color(player_color)
		spikes_visual.pop_spikes()

	if spike_hitbox:
		spike_hitbox.monitoring = true

func _stop_spiky() -> void:
	is_spiky = false

	if spikes_visual and spikes_visual.has_method("retract_spikes"):
		spikes_visual.retract_spikes()

	if spike_hitbox:
		spike_hitbox.monitoring = false

	if is_local_player and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		_sync_spiky.rpc(false)
