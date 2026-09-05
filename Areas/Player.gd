extends CharacterBody2D

# so ts is the player ball script, got all the juicy physics in here, rolling bouncing n controls n stuff

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

# sound players for jump/bounce (shared so they literally cant overlap, check
# _play_impact_sound below for why) and also death sound
@onready var impact_audio: AudioStreamPlayer = $ImpactAudio
@onready var death_audio: AudioStreamPlayer = $DeathAudio
@onready var dash_audio: AudioStreamPlayer = get_node_or_null("DashAudio")
@onready var spawn_audio: AudioStreamPlayer = get_node_or_null("SpawnAudio")
@onready var wind_trail: Node2D = get_node_or_null("WindTrail")
@onready var spikes_visual: Node2D = get_node_or_null("SpikesVisual")
@onready var spike_hitbox: Area2D = get_node_or_null("SpikeHitbox")

# mobile controls support fr fr, auto finds the MobileControls node if its there.
# typed as MobileControlsPanel (not just Node) so we can call its methods
# directly without has_method() reflection checks every single frame
var mobile_controls: MobileControlsPanel = null

const JUMP_STREAM: AudioStream = preload("res://Sounds/Pop.ogg")
const BOUNCE_STREAM: AudioStream = preload("res://Sounds/Tongue.ogg")


@export var player_id: int = 1
@export var player_color: Color = Color.WHITE
@export var player_display_name: String = "Player"

signal player_died(player_id: int)

# abilities/powers system, u zoom fast as heck n pop spikes basically
var equipped_powers: Array = ["dash"]
var is_dashing: bool = false
var dash_cooldown_timer: float = 0.0
var dash_time_remaining: float = 0.0
const DASH_COOLDOWN: float = 1.2
const DASH_DURATION: float = 0.22 # this gives it that nice beefy burst duration ngl
const DASH_SPEED: float = 950.0
var dash_direction: float = 1.0
var last_move_dir_x: float = 1.0

# spiky power, u grow sharp lil triangles that eliminate anyone u bump into lol
var is_spiky: bool = false
var spiky_time_remaining: float = 0.0
var spiky_cooldown_timer: float = 0.0
const SPIKY_DURATION: float = 3.5
const SPIKY_COOLDOWN: float = 4.5

var is_local_player: bool = true
var shader_mat: ShaderMaterial
var sprite_base_scale: Vector2 = Vector2.ONE

# --- remote player netcode state (only ever used when !is_local_player) ---
# _sync_transform arrives over an UNRELIABLE rpc, so packets can get dropped
# or arrive late. snapping straight to the latest position every time we get
# one reads as jittery teleporting whenever theres any packet loss. instead
# we dead-reckon forward each frame using the last velocity we heard about
# (so movement stays smooth even between packets), then gently blend any
# drift out against the newest authoritative position instead of snapping
var _net_target_position: Vector2 = Vector2.ZERO
var _net_target_rotation: float = 0.0
var _net_velocity: Vector2 = Vector2.ZERO
var _net_initialized: bool = false
const NET_CORRECTION_RATE: float = 48.0 # higher = snaps to the real position faster, lower = smoother but laggier

# ok so right after spawning the first couple physics frames can report a
# floor_normal thats juuust barely off from perfectly flat (0,-1) before the
# collision fully settles in, n without this grace window that tiny wobble
# reads as "bro's on a slope" n the roll-down-slopes code below yeets the
# ball sideways right out from under itself before the player even sees it land
var _spawn_grace_frames: int = 30

# each bounce fades the sound out so it gets quieter n quieter, kinda neat
var bounce_volume_db: float = 0.0
const BOUNCE_FADE_DB: float = 6.0     # how many dB quieter each bounce gets
const BOUNCE_MIN_DB: float = -40.0    # quiet enough that it just stops playing

# death handling, starts below the corner (in "the void") n rises up into view
# using the EXACT same velocity/gravity/move_and_slide a normal jump uses,
# peaks right in the corner spot matching the reference pic, then falls back
# down n out for good
var is_dead: bool = false
var death_entry_y: float = 0.0
const DEATH_SINK_MARGIN: float = 150.0 # how far past where it re-entered before it gets removed
const DEATH_RISE_MARGIN: float = 60.0  # extra distance below screen edge so the climb in is actually visible n not instant

const DEATH_ANCHOR_X: float = 1050.0   # base x, measured off the reference so the face reads fully
const DEATH_ANCHOR_Y: float = 570.0    # base y, same deal
const DEATH_STEP_X: float = 300.0      # each further simultaneous death steps this far left...
const DEATH_STEP_Y: float = 25.0       # ...n this far down so they dont stack on top of each other
const DEATH_SPRITE_SCALE: float = 0.8  # dead face size, matched to the ref proportions

# shared across every player instance so simultaneous deaths space themselves
# out in the corner instead of all landing on top of each other lol
static var dead_count: int = 0

static func reset_deaths() -> void:
	dead_count = 0

func _play_spawn_animation() -> void:
	# pop in animation when the player spawns, lil juice
	if sprite:
		sprite.scale = Vector2.ZERO
		var tween := create_tween()
		tween.tween_property(sprite, "scale", sprite_base_scale, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# play the spawn sound too
	if spawn_audio and spawn_audio.stream:
		spawn_audio.play()

func _play_death_pop_animation() -> void:
	# pop out animation when player dies, right before the sad face grows big
	if sprite:
		var tween := create_tween()
		# quick pop out then shrink back to zero
		tween.tween_property(sprite, "scale", sprite_base_scale * 1.3, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

func _ready() -> void:
	# gotta figure out if this ball is ours or some other dude's online
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		is_local_player = (player_id == multiplayer.get_unique_id())
		set_multiplayer_authority(player_id)
	else:
		is_local_player = true
		player_color = PlayerData.skin_color
		player_display_name = PlayerData.player_name
		equipped_powers = PlayerData.equipped_powers.duplicate()

	# slap the recolor shader on the ball so the color actually shows up fr
	if sprite:
		sprite_base_scale = sprite.scale
		var shader = load("res://Character/recolor.gdshader") as Shader
		shader_mat = ShaderMaterial.new()
		shader_mat.shader = shader
		shader_mat.set_shader_parameter("skin_color", player_color)
		sprite.material = shader_mat

	# show the gamer tag floating above the ball
	if name_label:
		name_label.text = player_display_name

	# slope physics tweaks so we slide down hills like an actual ball would
	floor_stop_on_slope = false
	floor_constant_speed = false
	floor_max_angle = deg_to_rad(65.0)
	floor_snap_length = 12.0

	add_to_group("player")

	if spike_hitbox:
		spike_hitbox.body_entered.connect(_on_spike_hitbox_body_entered)

	if spikes_visual and spikes_visual.has_method("set_color"):
		spikes_visual.set_color(player_color)

	# go find the mobile controls if they exist on this device
	_find_mobile_controls()
	
	# spawn pop in anim, gotta have that juice
	_play_spawn_animation()

func _find_mobile_controls() -> void:
	# grab the autoloaded MobileControls singleton if it exists
	mobile_controls = get_node_or_null("/root/MobileControls") as MobileControlsPanel
	
	# make the buttons match the player color so it feels cohesive
	if mobile_controls:
		mobile_controls.set_button_colors(player_color)
		# n only show the power buttons (dash/spiky) we actually equipped or
		# smth, but ONLY for our own ball, dont want some remote guy's
		# loadout messing w our buttons
		if is_local_player:
			mobile_controls.set_equipped_powers(equipped_powers)



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
	
	# update the mobile buttons to match the (maybe new) player color
	if is_local_player and mobile_controls:
		mobile_controls.set_button_colors(player_color)
		mobile_controls.set_equipped_powers(equipped_powers)


func die() -> void:
	# never process a death twice for the same ball lol (like void zone AND
	# something else calling die() same frame, dont wanna double dip that)
	if is_dead:
		return
	is_dead = true
	
	# play the death pop anim first
	_play_death_pop_animation()
	
	is_dashing = false
	if is_spiky:
		_stop_spiky()
	if wind_trail and wind_trail.has_method("stop_trail"):
		wind_trail.stop_trail()
	player_died.emit(player_id)

	# stop taking part in gameplay physics/collision entirely, the death hop
	# below is its own lil fake-gravity animation, not real collision anymore
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0

	# a fresh death shouldnt leak a still-playing jump/bounce sound into it
	if impact_audio and impact_audio.playing:
		impact_audio.stop()

	# swap to the sad face texture n blow it up to corner-avatar size
	if sprite:
		var sad_tex := load("res://Character/CharacterSad.svg") as Texture2D
		if sad_tex:
			sprite.texture = sad_tex
		sprite.rotation = 0.0
		sprite.scale = sprite_base_scale * (DEATH_SPRITE_SCALE / 0.19)

	# the gamer tag doesnt scale with the sprite so it just floats weird in
	# the middle of the big dead face, just hide it, matches the ref look better
	if name_label:
		name_label.visible = false

	# sad trombone noise lmao
	if death_audio and death_audio.stream:
		death_audio.play()

	# figure out this death's slot in the corner, each simultaneous death claims
	# the next one, stepping further left n slightly further down than the last
	var death_index := dead_count
	dead_count += 1
	var anchor_x := DEATH_ANCHOR_X - death_index * DEATH_STEP_X
	var anchor_y := DEATH_ANCHOR_Y + death_index * DEATH_STEP_Y

	# the sad face sprite is WAY bigger than the ball so hiding just its
	# center below the screen aint enough, top of a tall sprite can still
	# poke into view right away. gotta measure how tall it actually renders
	# rn (after the texture swap n scale change above) so we know how far
	# down its top edge really sits
	var sprite_half_height: float = 0.0
	if sprite and sprite.texture:
		sprite_half_height = sprite.texture.get_height() * sprite.scale.y * 0.5

	# start low enough that the WHOLE sprite is below the visible area, plus
	# a lil extra so theres a beat of travel before it crosses the bottom
	# edge, thats what reads as climbing outta the ground instead of just
	# teleporting into view
	var screen_bottom: float = get_viewport_rect().size.y
	var hidden_y: float = screen_bottom + sprite_half_height + DEATH_RISE_MARGIN
	var required_rise: float = max(hidden_y - anchor_y, 0.0)

	# solve for the launch speed that makes a normal gravity arc (same
	# gravity/move_and_slide the rest of the game uses for jumping) peak
	# exactly at the corner spot after covering that whole distance, math ig
	var gravity_y: float = get_gravity().y
	var launch_velocity_y: float = -sqrt(2.0 * gravity_y * required_rise) if gravity_y > 0.0 else jump_velocity

	death_entry_y = anchor_y + required_rise
	global_position = Vector2(anchor_x, death_entry_y)

	# launch it up at that solved speed, every frame from here uses the exact
	# same gravity + move_and_slide() as a normal jump too (see
	# _death_physics_process below) so it decelerates n settles into the
	# corner just like landing a jump would
	velocity = Vector2(0.0, launch_velocity_y)

func _physics_process(delta: float) -> void:
	# dead balls run their own tiny gravity sim instead of the normal movement code
	if is_dead:
		_death_physics_process(delta)
		return

	# if this aint our ball, let the network sync move it instead, we just
	# interpolate towards whatever the last update said instead of touching
	# any of the local physics/input stuff below
	if not is_local_player:
		_remote_interpolate(delta)
		return

	var gravity = get_gravity()
	
	# check if mobile controls active, only declare this once at top of the func.
	# no has_method() reflection needed anymore since mobile_controls is
	# properly typed now, just calls the method straight up
	var mobile_active = mobile_controls != null and mobile_controls.is_active()

	# snapshot whether jump is being held ONCE per frame, right up front, so ts
	# stays consistent for the rest of the frame n doesnt get read twice n desync
	var jump_held: bool = Input.is_action_pressed("jump") or Input.is_action_pressed("ui_accept")
	
	# mobile controls support too
	if mobile_active and mobile_controls.is_jump_pressed():
		jump_held = true

	# falling n slope sliding stuff
	if not is_on_floor():
		velocity += gravity * delta
	else:
		# roll down slopes naturally like a real lil ball
		if _spawn_grace_frames > 0:
			_spawn_grace_frames -= 1
		else:
			var floor_normal = get_floor_normal()
			# use a tolerance instead of exact equality, physics computed
			# normals are basically never bit-exact (0,-1) even on perfectly
			# flat ground, so an exact != comparison misreads flat floors as
			# slopes n adds a tiny sideways push every single frame. harmless
			# on one big continuous floor where u cant even tell, but on a
			# narrow floating platform it slowly rolls the ball right off the edge
			if floor_normal != Vector2.ZERO and floor_normal.dot(Vector2.UP) < 0.999:
				var slope_tangent = Vector2(floor_normal.y, -floor_normal.x)
				var slope_pull = gravity.dot(slope_tangent)
				velocity += slope_tangent * slope_pull * delta * 0.85

	# input handling: wasd / arrows / mobile joystick, or hold left click to steer
	var input_x: float = 0.0

	# 1. mobile joystick, takes priority if its actually present
	if mobile_active:
		var joystick_vec = mobile_controls.get_joystick_vector()
		if abs(joystick_vec.x) > 0.05:
			input_x = joystick_vec.x
	
	# 2. keyboard / dpad if theres no mobile input
	if input_x == 0.0:
		input_x = Input.get_axis("ui_left", "ui_right")
		if input_x == 0.0:
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
				input_x -= 1.0
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
				input_x += 1.0

	# 3. mouse steer, hold left click n the ball rolls toward ur cursor (DISABLED on mobile)
	if input_x == 0.0 and not mobile_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse_pos = get_global_mouse_position()
		var diff_x = mouse_pos.x - global_position.x
		if abs(diff_x) > 16.0:
			input_x = clamp(diff_x / 100.0, -1.0, 1.0)

	# when spiky's popped manual steering is locked!! momentum just rolls naturally
	if is_spiky:
		input_x = 0.0

	# speed up or coast smooth with inertia so it rolls a bit further, feels nicer
	var current_friction = friction if is_on_floor() else air_friction
	if abs(input_x) > 0.05:
		velocity.x = move_toward(velocity.x, input_x * speed, acceleration * delta)
		last_move_dir_x = sign(input_x)
	else:
		# coasting to a stop
		velocity.x = move_toward(velocity.x, 0.0, current_friction * delta)

	# dash cooldown n input handling
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = max(dash_cooldown_timer - delta, 0.0)

	var dash_just_pressed = Input.is_action_just_pressed("dash")
	if mobile_active and mobile_controls.is_dash_just_pressed():
		dash_just_pressed = true
	
	if dash_just_pressed:
		_try_dash(input_x)

	if is_dashing:
		dash_time_remaining -= delta
		velocity.x = dash_direction * DASH_SPEED
		velocity.y = min(velocity.y, 0.0)
		if dash_time_remaining <= 0.0:
			_stop_dash()

	# spiky ability timer n trigger
	if spiky_cooldown_timer > 0.0:
		spiky_cooldown_timer = max(spiky_cooldown_timer - delta, 0.0)

	var spiky_just_pressed = Input.is_action_just_pressed("spiky")
	if mobile_active and mobile_controls.is_spiky_just_pressed():
		spiky_just_pressed = true
	
	if spiky_just_pressed:
		_try_spiky()

	if is_spiky:
		spiky_time_remaining -= delta
		if spiky_time_remaining <= 0.0:
			_stop_spiky()

	# jump w/ space / w / up arrow / mobile button (edge triggered so holding it
	# down doesnt spam jump every frame, learned that one the hard way)
	var jump_pressed = Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept")
	if mobile_active and mobile_controls.is_jump_just_pressed():
		jump_pressed = true
	
	if jump_pressed and is_on_floor():
		velocity.y = jump_velocity
		# play the pop sound n reset bounce volume for whenever it lands next
		bounce_volume_db = 0.0
		_play_jump_sound()

	# remember the speed before collision so we can do sick bounces off it
	var pre_move_vel = velocity

	# move the body, this is where the actual collision happens
	move_and_slide()

	# ball bounce restitution: hit the ground n boing with fading volume each
	# hop. uses the SAME jump_held snapshot from the top of this frame, no
	# second read here, thats on purpose so it stays in sync w what actually happened
	if is_on_floor() and pre_move_vel.y > min_bounce_speed:
		if jump_held:
			# still holding jump while landing? skip the bounce n just jump again
			velocity.y = jump_velocity
			bounce_volume_db = 0.0
			_play_jump_sound()
		else:
			velocity.y = -pre_move_vel.y * bounce_factor
			_play_bounce_sound()
	elif is_on_ceiling() and pre_move_vel.y < -min_bounce_speed:
		velocity.y = -pre_move_vel.y * bounce_factor
		_play_bounce_sound()

	# bounce off walls if we slam into em fast enough, satisfying af
	if is_on_wall() and abs(pre_move_vel.x) > min_bounce_speed:
		velocity.x = -pre_move_vel.x * (bounce_factor * 0.75)

	# make the ball sprite actually roll n spin while its moving, lil detail but it matters
	if sprite:
		sprite.rotation += (velocity.x * delta) / ball_radius
		if spikes_visual:
			spikes_visual.rotation = sprite.rotation

	# so ts makes like so the player position gets syncronizated across everyone
	# else's screen too, basically we just spam our transform out over rpc so
	# the other clients see us rolling around in real time n it doesnt look laggy
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		_sync_transform.rpc(global_position, sprite.rotation if sprite else 0.0, velocity)

func _death_physics_process(delta: float) -> void:
	# identical integration to a normal jump, accumulate gravity into velocity
	# then move_and_slide(), same property same call same order of ops fr.
	# collision is off (layer/mask 0) so nothing blocks it, it just arcs freely
	velocity += get_gravity() * delta
	move_and_slide()

	# its falling back down now (not still rising) n has sunk well past where
	# it re-entered, so its gone into the void for good, remove it from the scene
	if velocity.y > 0.0 and global_position.y >= death_entry_y + DEATH_SINK_MARGIN:
		queue_free()

func _remote_interpolate(delta: float) -> void:
	# runs on every OTHER peer's machine to move a non-local ball smoothly.
	# dead reckon the target forward using the last velocity we heard about
	# so it keeps rolling between packets instead of freezing, then blend
	# our actual displayed position toward that target instead of snapping
	# to it directly, that blend is what soaks up jitter/packet loss n makes
	# it look like it never dropped a single packet even when it did
	if not _net_initialized:
		return

	_net_target_position += _net_velocity * delta

	var correction: float = clamp(NET_CORRECTION_RATE * delta, 0.0, 1.0)
	global_position = global_position.lerp(_net_target_position, correction)
	velocity = _net_velocity

	if sprite:
		sprite.rotation = lerp_angle(sprite.rotation, _net_target_rotation, correction)
		if spikes_visual:
			spikes_visual.rotation = sprite.rotation

func _play_jump_sound() -> void:
	if impact_audio:
		impact_audio.stream = JUMP_STREAM
		impact_audio.pitch_scale = 1.0
		impact_audio.volume_db = 0.0
		impact_audio.play()

func _play_bounce_sound() -> void:
	if bounce_volume_db <= BOUNCE_MIN_DB:
		return
	if impact_audio:
		impact_audio.stream = BOUNCE_STREAM
		impact_audio.pitch_scale = 1.0
		impact_audio.volume_db = bounce_volume_db
		impact_audio.play()
	bounce_volume_db -= BOUNCE_FADE_DB

# this is the actual sync rpc that runs on every OTHER peer's machine to move
# our ball around on their screen, keeps everyone lookin synced up basically.
# doesnt snap position directly anymore, just feeds the interpolation target
# that _remote_interpolate() smooths towards every physics frame
@rpc("unreliable")
func _sync_transform(pos: Vector2, rot: float, vel: Vector2) -> void:
	if is_local_player:
		return
	_net_target_position = pos
	_net_target_rotation = rot
	_net_velocity = vel

	if not _net_initialized:
		# first packet we've ever gotten for this ball, snap straight to it
		# so it doesnt slide in all the way from the origin (0,0)
		global_position = pos
		if sprite:
			sprite.rotation = rot
		_net_initialized = true

func _try_dash(input_x: float) -> void:
	# bro pressed dash, gotta check if were even allowed to send it rn
	if not equipped_powers.has("dash"):
		return
	if dash_cooldown_timer > 0.0 or is_dead:
		return

	# figure out which way to blast off
	var dir: float = sign(input_x)
	if dir == 0.0:
		dir = last_move_dir_x if last_move_dir_x != 0.0 else 1.0

	_start_dash(dir)

	# tell the lobby boys we just dashed so they see the wind trail too
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		_sync_dash.rpc(dash_direction)

@rpc("unreliable")
func _sync_dash(dir: float) -> void:
	# other player dashed, fire off the visual fx on our screen too
	if is_local_player:
		return
	_start_dash(dir)

func _start_dash(dir: float) -> void:
	# blast off with speed lines trailing behind, real anime hours
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
	# dash impulse done, fade the trail out smooth
	is_dashing = false
	if wind_trail and wind_trail.has_method("stop_trail"):
		wind_trail.stop_trail()

	# gotta tell the lobby boys the dash is over too or smth, otherwise their
	# copy of our ball never hears about it (remote balls skip the local dash
	# timer entirely, see _physics_process up top) n the trail just sits there forever lol
	if is_local_player and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		_sync_dash_stop.rpc()

@rpc("reliable")
func _sync_dash_stop() -> void:
	# other player's dash ended, kill the wind trail fx on our screen too ig.
	# ts one's reliable tho (unlike the start/move rpcs) since it only fires
	# once n a dropped packet here means the trail literally never goes away
	if is_local_player:
		return
	_stop_dash()

func _play_dash_sound() -> void:
	# high pitched pop for that anime dash whoosh sound lol
	if dash_audio:
		dash_audio.play()
	elif impact_audio:
		impact_audio.stream = JUMP_STREAM
		impact_audio.pitch_scale = 1.65
		impact_audio.volume_db = 2.0
		impact_audio.play()

func _on_spike_hitbox_body_entered(body: Node2D) -> void:
	# spiky lethal touch, if we bump into an enemy player while covered in
	# spikes theyre cooked, no cap
	if not is_spiky:
		return
	if body == self:
		return
	if body.has_method("die") and ("is_dead" in body and not body.is_dead):
		body.die()

func _try_spiky() -> void:
	# bro pressed spiky, check if its equipped n actually ready to go
	if not equipped_powers.has("spiky"):
		return
	if spiky_cooldown_timer > 0.0 or is_dead or is_spiky:
		return

	_start_spiky()

	# tell everyone in the lobby we just sprouted spikes lmao
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
