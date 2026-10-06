extends CharacterBody2D

# so ts is the player ball script, got all the juicy physics in here, rolling bouncing n controls n stuff

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")

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
@export var is_tutorial_dummy: bool = false

signal player_died(player_id: int)

# abilities/powers system, u zoom fast as heck n pop spikes basically
var equipped_powers: Array = ["dash"]
var is_dashing: bool = false
var dash_cooldown_timer: float = 0.0
var dash_time_remaining: float = 0.0
const DASH_COOLDOWN: float = 2.0 # every power shares the same 2s cooldown now, keeps it fair across the board
const DASH_DURATION: float = 0.22 # this gives it that nice beefy burst duration ngl
const DASH_SPEED: float = 950.0
var dash_direction: float = 1.0
var last_move_dir_x: float = 1.0

# spiky power, u grow sharp lil triangles that eliminate anyone u bump into lol
var is_spiky: bool = false
var spiky_time_remaining: float = 0.0
var spiky_cooldown_timer: float = 0.0
const SPIKY_DURATION: float = 3.5
const SPIKY_COOLDOWN: float = 2.0

# bomb power, pull it out, chuck it n run, or get greedy n hold it too long lmao.
# sprite lives at res://Menu/Bomb.png, loaded at runtime (not preloaded) so the
# project doesnt refuse to boot if that art hasnt actually been dropped in yet
var is_holding_bomb: bool = false
var bomb_hold_timer: float = 0.0
var bomb_startup_frames_remaining: int = 0
var bomb_cooldown_timer: float = 0.0
var _bomb_hold_sprite: Sprite2D = null
var bomb_aim_dir: Vector2 = Vector2.RIGHT # which way ur currently pointing the bomb, follows the mouse
const BOMB_FUSE_TIME: float = 3.5       # same long cook window as bopl so u can line up a real trick shot
const BOMB_COOLDOWN: float = 2.0
const BOMB_STARTUP_FRAMES: int = 14     # ~0.2s @ 60fps, the windup before u can actually chuck it
const BOMB_THROW_FORCE: float = 520.0   # actual chuck speed now, not a lazy drop
const BOMB_EXPLOSION_RADIUS: float = 90.0
const BOMB_HOLD_SCALE: float = 0.17     # bomb art is 256x256, this gets it down to roughly half the ball's size
const BOMB_HOLD_RADIUS: float = 44.0    # how far from the ball's center the held bomb sits, orbits around this
const BOMB_SPAWN_DISTANCE: float = 62.0
const BombScene: PackedScene = preload("res://Character/Bomb.tscn")
var _bomb_sequence: int = 0

var is_local_player: bool = true
var shader_mat: ShaderMaterial
var sprite_base_scale: Vector2 = Vector2.ONE

# remote balls coast between updates n ease back toward the real position,
# with anti-tunneling physics so high latency doesnt make bro clip through blocks
var _net_target_position: Vector2 = Vector2.ZERO
var _net_target_rotation: float = 0.0
var _net_velocity: Vector2 = Vector2.ZERO
var _net_initialized: bool = false
var _net_sync_timer: float = 0.0
var _net_seq: int = 0
var _latest_net_seq: int = 0
var _time_since_packet: float = 0.0
const NET_TICK_INTERVAL: float = 0.04 # 25 Hz send rate, keeps websocket buffer nice n clean
const MAX_EXTRAPOLATE_TIME: float = 0.10 # dont let the bro rocket across dimensions when lagging

# give fresh spawns a beat to settle before slope rolling kicks in
var _spawn_grace_frames: int = 30

# each bounce fades the sound out so it gets quieter n quieter, kinda neat
var bounce_volume_db: float = 0.0
const BOUNCE_FADE_DB: float = 6.0     # how many dB quieter each bounce gets
const BOUNCE_MIN_DB: float = -40.0    # quiet enough that it just stops playing

# death handling: gray the ball n pop it away while the lil death mark hangs around
var is_dead: bool = false
var _visual_tween: Tween
var _death_sprite_rotation: float = 0.0

func _play_spawn_animation() -> void:
	# pop in animation when the player spawns, lil juice
	if sprite:
		if _visual_tween and _visual_tween.is_running():
			_visual_tween.kill()
		sprite.scale = Vector2.ZERO
		_visual_tween = create_tween()
		_visual_tween.tween_property(sprite, "scale", sprite_base_scale, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# play the spawn sound too
	if spawn_audio and spawn_audio.stream:
		spawn_audio.play()

func _play_death_pop_animation() -> void:
	if not sprite:
		return
	if _visual_tween and _visual_tween.is_running():
		_visual_tween.kill()

	# grayscale n then reverse the DRAW banner pop so the ball vanishes clean
	if shader_mat:
		shader_mat.set_shader_parameter("skin_color", Color(0.5, 0.5, 0.5))
	else:
		sprite.modulate = Color(0.5, 0.5, 0.5)

	sprite.visible = true
	sprite.rotation = _death_sprite_rotation
	sprite.scale = sprite_base_scale
	_visual_tween = create_tween()
	var death_position := position
	var shake_offsets: Array[Vector2] = [
		Vector2(5.0, -2.0), Vector2(-5.0, 1.0), Vector2(4.0, 2.0),
		Vector2(-4.0, -1.0), Vector2(3.0, 1.0), Vector2(-3.0, 0.0), Vector2.ZERO
	]
	# lil panic shake first, then the ball n its name pop away together
	for offset in shake_offsets:
		_visual_tween.tween_property(self, "position", death_position + offset, 0.045).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_visual_tween.tween_property(sprite, "scale", Vector2.ZERO, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if name_label:
		_visual_tween.parallel().tween_property(name_label, "scale", Vector2.ZERO, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

func _has_network_peer() -> bool:
	# Godot always gives solo games an OfflineMultiplayerPeer, so just checking
	# for a peer makes solo play act like its waiting on an actual lobby host.
	if not multiplayer.has_multiplayer_peer():
		return false
	var active_peer := multiplayer.multiplayer_peer
	return active_peer != null and not (active_peer is OfflineMultiplayerPeer)

func _ready() -> void:
	# gotta figure out if this ball is ours or some other dude's online
	if is_tutorial_dummy:
		# tutorial targets act like bodies, not like another controller
		is_local_player = false
	elif _has_network_peer():
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
	if mobile_controls and is_local_player:
		mobile_controls.set_button_colors(player_color)
		# n only show the power buttons (dash/spiky) we actually equipped or
		# smth, but ONLY for our own ball, dont want some remote guy's
		# loadout messing w our buttons
		mobile_controls.set_equipped_powers(equipped_powers)



func setup_player(id: int, p_name: String, color: Color, powers: Array = ["dash"]) -> void:
	player_id = id
	player_display_name = p_name
	player_color = color
	equipped_powers = powers.duplicate()

	if _has_network_peer():
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
	if is_dead:
		return
	if _has_network_peer():
		var network_mgr = get_node_or_null("/root/NetworkManager")
		if not NetworkManagerScript.is_host:
			# only the owning client can report its own local collision result
			if not is_local_player:
				return
			_finish_death()
			if network_mgr:
				network_mgr.report_player_death(player_id)
			return
		if network_mgr:
			network_mgr.report_player_death(player_id)
			return
	_finish_death()

func apply_authoritative_death() -> void:
	# host-approved death arrives here so it doesnt get re-reported back to host
	_finish_death()

func _finish_death() -> void:
	# never process a death twice for the same ball lol (like void zone AND
	# something else calling die() same frame, dont wanna double dip that)
	if is_dead:
		return
	is_dead = true
	if sprite:
		_death_sprite_rotation = sprite.rotation

	is_dashing = false
	if is_spiky:
		_stop_spiky()
	if is_holding_bomb:
		is_holding_bomb = false
		_hide_bomb_hold_visual()
		if is_local_player and _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
			_sync_bomb_hold.rpc(false)
	if wind_trail and wind_trail.has_method("stop_trail"):
		wind_trail.stop_trail()

	# stop taking part in gameplay physics/collision entirely
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	player_died.emit(player_id)

	# a fresh death shouldnt leak a still-playing jump/bounce sound into it
	if impact_audio and impact_audio.playing:
		impact_audio.stop()

	# keep the death marker readable while the ball does its pop-out bit
	if spikes_visual:
		spikes_visual.visible = false

	if name_label:
		name_label.text = player_display_name + " ✕"
		name_label.visible = true
		name_label.scale = Vector2.ONE
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.pivot_offset = name_label.size * 0.5

	_play_death_pop_animation()

	# sad trombone noise lmao
	if death_audio and death_audio.stream:
		death_audio.play()

	# stick around silently for a beat so the text/sound actually register
	var tree := get_tree()
	if not tree:
		return
	await tree.create_timer(1.0).timeout
	if not is_inside_tree():
		return
	_on_death_cleanup_complete()

func _on_death_cleanup_complete() -> void:
	# regular players are done here; tutorial dummies override this n pop back in
	queue_free()

func _physics_process(delta: float) -> void:
	# dead balls dont do anything anymore, just sit there as text til they're freed
	if is_dead:
		return
	if NetworkManagerScript.is_scene_transitioning:
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

	# if pause menu or match menu overlay is open, dont leak any keys through lol
	# clicking sliders or typing shouldnt make ur ball dash into the abyss
	var match_menu_open := false
	for menu_overlay in get_tree().get_nodes_in_group("match_menu_overlay"):
		if bool(menu_overlay.get("menu_is_open")):
			match_menu_open = true
			break

	# snapshot whether jump is being held ONCE per frame, right up front, so ts
	# stays consistent for the rest of the frame n doesnt get read twice n desync
	var jump_held: bool = false
	if not match_menu_open:
		jump_held = Input.is_action_pressed("jump") or Input.is_action_pressed("ui_accept")
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
			# floor normals wobble a tiny bit, so dont call every flat tile a slope
			if floor_normal != Vector2.ZERO and floor_normal.dot(Vector2.UP) < 0.999:
				var slope_tangent = Vector2(floor_normal.y, -floor_normal.x)
				var slope_pull = gravity.dot(slope_tangent)
				velocity += slope_tangent * slope_pull * delta * 0.85

	# input handling: wasd / arrows / mobile joystick, or hold left click to steer
	var input_x: float = 0.0

	# ignore inputs if paused or in a menu lol
	if not match_menu_open:
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

	# 3. mouse steer used to live here (hold left click to roll toward cursor),
	# but left click is now Power Slot 1's trigger button, so it got removed
	# to stop the two fighting each other every time u click

	# when spiky's popped OR ur holding a bomb, manual steering is locked!!
	# momentum just rolls naturally, cant fight it
	if is_spiky or is_holding_bomb:
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

	var dash_just_pressed = false
	if not match_menu_open:
		dash_just_pressed = Input.is_action_just_pressed("dash")
		if mobile_active and mobile_controls.is_dash_just_pressed():
			dash_just_pressed = true
	
	if dash_just_pressed:
		_try_dash(input_x)

	# bomb cooldown ticks down same as the other two
	if bomb_cooldown_timer > 0.0:
		bomb_cooldown_timer = max(bomb_cooldown_timer - delta, 0.0)

	var bomb_just_pressed = false
	var bomb_just_released = false
	if not match_menu_open:
		bomb_just_pressed = Input.is_action_just_pressed("bomb")
		if mobile_active and mobile_controls.has_method("is_bomb_just_pressed") and mobile_controls.is_bomb_just_pressed():
			bomb_just_pressed = true
		bomb_just_released = Input.is_action_just_released("bomb")
		if mobile_active and mobile_controls.has_method("is_bomb_just_released") and mobile_controls.is_bomb_just_released():
			bomb_just_released = true

	if bomb_just_pressed:
		_try_bomb()

	if bomb_just_released:
		_release_bomb()

	# power slots: whatever ability sits in equip slot 1/2/3 fires off the
	# matching mouse button (left/middle/right). lets us just swap the array
	# order in the loadout menu instead of hardcoding one button per power
	# clicking a settings slider shouldnt also fire an attack at somebody lol
	for slot_index in range(min(equipped_powers.size(), 3)):
		var slot_action := "power_slot_%d" % (slot_index + 1)
		var slot_power: String = equipped_powers[slot_index]
		var mouse_slot_pressed := Input.is_action_just_pressed(slot_action)
		var mouse_slot_released := Input.is_action_just_released(slot_action)
		if mobile_active:
			# real mouse clicks work on phones too; touch-emulated clicks stay with
			# the on-screen buttons so a random tap doesnt fire slot one lol
			mouse_slot_pressed = mobile_controls.consume_mouse_slot_just_pressed(slot_index)
			mouse_slot_released = mobile_controls.consume_mouse_slot_just_released(slot_index)
		if not match_menu_open and mouse_slot_pressed:
			_try_power(slot_power, input_x)
		if not match_menu_open and slot_power == "bomb" and mouse_slot_released:
			_release_bomb()

	# bomb hold ticking: startup windup counts down, n if u greedily hold it
	# past the limit it just goes off in ur hands, no throw, no mercy.
		# keep tracking the aim so the bomb circles the ball at a fixed lil radius
	if is_holding_bomb:
		if bomb_startup_frames_remaining > 0:
			bomb_startup_frames_remaining -= 1
		bomb_hold_timer += delta

		if mobile_active and not mobile_controls.has_physical_mouse_input():
			# joystick points the held bomb around its little orbit on phones
			var joystick_aim: Vector2 = mobile_controls.get_joystick_vector()
			if joystick_aim.length() > 0.15:
				bomb_aim_dir = joystick_aim.normalized()
		else:
			var to_mouse: Vector2 = get_global_mouse_position() - global_position
			if to_mouse.length() > 1.0:
				bomb_aim_dir = to_mouse.normalized()
		if _bomb_hold_sprite:
			_bomb_hold_sprite.position = bomb_aim_dir * BOMB_HOLD_RADIUS

		if bomb_hold_timer >= BOMB_FUSE_TIME:
			_detonate_held_bomb()

	if is_dashing:
		dash_time_remaining -= delta
		velocity.x = dash_direction * DASH_SPEED
		velocity.y = min(velocity.y, 0.0)
		if dash_time_remaining <= 0.0:
			_stop_dash()

	# spiky ability timer n trigger
	if spiky_cooldown_timer > 0.0:
		spiky_cooldown_timer = max(spiky_cooldown_timer - delta, 0.0)

	var spiky_just_pressed = false
	if not match_menu_open:
		spiky_just_pressed = Input.is_action_just_pressed("spiky")
		if mobile_active and mobile_controls.is_spiky_just_pressed():
			spiky_just_pressed = true
	
	if spiky_just_pressed:
		_try_spiky()

	if is_spiky:
		spiky_time_remaining -= delta
		if spiky_time_remaining <= 0.0:
			_stop_spiky()

	# jump w/ space / w / up arrow / mobile button (edge triggered so holding it
	# down doesnt spam jump every frame, learned that one the hard way).
	# blocked while spiky's popped or ur holding a bomb, same as steering
	var jump_pressed = false
	if not match_menu_open:
		jump_pressed = Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept")
		if mobile_active and mobile_controls.is_jump_just_pressed():
			jump_pressed = true
	
	if jump_pressed and is_on_floor() and not is_spiky and not is_holding_bomb:
		velocity.y = jump_velocity
		# play the pop sound n reset bounce volume for whenever it lands next
		bounce_volume_db = 0.0
		_play_jump_sound()
		_net_sync_timer = 0.0

	# remember the speed before collision so we can do sick bounces off it
	var pre_move_vel = velocity

	# move the body, this is where the actual collision happens
	move_and_slide()

	# ball bounce restitution: hit the ground n boing with fading volume each
	# hop. uses the SAME jump_held snapshot from the top of this frame, no
	# second read here, thats on purpose so it stays in sync w what actually happened
	if is_on_floor() and pre_move_vel.y > min_bounce_speed:
		if jump_held and not is_spiky and not is_holding_bomb:
			# still holding jump while landing? skip the bounce n just jump again
			velocity.y = jump_velocity
			bounce_volume_db = 0.0
			_play_jump_sound()
			_net_sync_timer = 0.0
		else:
			velocity.y = -pre_move_vel.y * bounce_factor
			_play_bounce_sound()
			_net_sync_timer = 0.0
	elif is_on_ceiling() and pre_move_vel.y < -min_bounce_speed:
		velocity.y = -pre_move_vel.y * bounce_factor
		_play_bounce_sound()
		_net_sync_timer = 0.0

	# bounce off walls if we slam into em fast enough, satisfying af
	if is_on_wall() and abs(pre_move_vel.x) > min_bounce_speed:
		velocity.x = -pre_move_vel.x * (bounce_factor * 0.75)
		_play_bounce_sound()
		_net_sync_timer = 0.0

	# make the ball sprite actually roll n spin while its moving, lil detail but it matters
	if sprite:
		sprite.rotation += (velocity.x * delta) / ball_radius
		if spikes_visual:
			spikes_visual.rotation = sprite.rotation

	# throttle transform sync to ~25 Hz so we dont drown the websocket buffer
	# on high latency connections (looking at u, international routing)
	_net_sync_timer -= delta
	if _net_sync_timer <= 0.0:
		_net_sync_timer = NET_TICK_INTERVAL
		if _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
			_net_seq += 1
			_sync_transform.rpc(global_position, sprite.rotation if sprite else 0.0, velocity, bomb_aim_dir, _net_seq)

func _remote_interpolate(delta: float) -> void:
	# ts manages remote prediction n interpolation so high ping doesnt look like a slideshow
	if not _net_initialized:
		return

	_time_since_packet += delta

	# bro is on 400ms from the other side of the planet, dont let him phase into the 4th dimension
	# only dead-reckon extrapolate for a brief slice (~0.10s / ~2.5 ticks)
	# if packets are lagging behind, apply friction so remote ball coasts to a stop
	# instead of rocketing straight through the stage blocks
	if _time_since_packet < MAX_EXTRAPOLATE_TIME:
		_net_target_position += _net_velocity * delta
	else:
		_net_velocity = _net_velocity.move_toward(Vector2.ZERO, 800.0 * delta)
		_net_target_position += _net_velocity * delta

	var to_target: Vector2 = _net_target_position - global_position
	var dist: float = to_target.length()

	# if bro is completely off the rails (respawn, death warp, or giant >260px gap), just snap straight up
	if dist > 260.0:
		global_position = _net_target_position
		velocity = _net_velocity
	else:
		# smooth catch-up velocity: blend reported velocity with pull towards target
		var catch_up_speed: float = clamp(dist * 18.0, 0.0, 1400.0)
		var target_pull: Vector2 = to_target.normalized() * catch_up_speed
		
		if _net_velocity.length() > 20.0:
			velocity = _net_velocity.lerp(target_pull, 0.45)
		else:
			velocity = target_pull

		# use move_and_slide so remote balls actually respect walls instead of noclipping like gmod!
		move_and_slide()

		# when close enough, smoothly pull the remaining sub-pixel/minor drift
		# if stuck on a lip/corner with error building up, softly ease it over
		if dist < 45.0:
			global_position = global_position.lerp(_net_target_position, clamp(16.0 * delta, 0.0, 1.0))
		elif dist > 90.0 and get_slide_collision_count() > 0:
			# ball hit a snag or corner desync, gently nudge it toward real target so it doesn't get permanently wedged
			global_position = global_position.lerp(_net_target_position, clamp(6.0 * delta, 0.0, 1.0))

	# roll n rotate the ball smoothly
	if sprite:
		sprite.rotation = lerp_angle(sprite.rotation, _net_target_rotation, clamp(18.0 * delta, 0.0, 1.0))
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

# feed remote movement into the smoother instead of snapping the ball outright
@rpc("unreliable_ordered")
func _sync_transform(pos: Vector2, rot: float, vel: Vector2, aim_dir: Vector2 = Vector2.RIGHT, seq: int = 0) -> void:
	if is_local_player:
		return
	if seq > 0 and seq < _latest_net_seq:
		return # stale packet arrived out of order, toss it
	_latest_net_seq = seq
	_time_since_packet = 0.0
	_net_target_position = pos
	_net_target_rotation = rot
	_net_velocity = vel

	# mirror the thrower's current aim so a remote ball's held bomb orbits
	# toward the same spot theirs does, instead of just sitting frozen
	# wherever it first spawned in
	if is_holding_bomb and aim_dir.length() > 0.01:
		bomb_aim_dir = aim_dir
		if _bomb_hold_sprite:
			_bomb_hold_sprite.position = bomb_aim_dir * BOMB_HOLD_RADIUS

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
	if dash_cooldown_timer > 0.0 or is_dead or is_spiky or is_holding_bomb:
		return

	# figure out which way to blast off
	var dir: float = sign(input_x)
	if dir == 0.0:
		dir = last_move_dir_x if last_move_dir_x != 0.0 else 1.0

	_start_dash(dir)

	# tell the lobby boys we just dashed so they see the wind trail too
	if _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
		_sync_dash.rpc(dash_direction)
		# blast out a sync tick immediately so the burst speed hits right away
		_net_sync_timer = 0.0

@rpc("reliable")
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
	if is_local_player and _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
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
	if spiky_cooldown_timer > 0.0 or is_dead or is_spiky or is_holding_bomb:
		return

	_start_spiky()

	# tell everyone in the lobby we just sprouted spikes lmao
	if _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
		_sync_spiky.rpc(true)

@rpc("reliable")
func _sync_spiky(active: bool) -> void:
	if is_local_player:
		return
	if active:
		_start_spiky()
	else:
		_stop_spiky()

func _start_spiky() -> void:
	# dont let an old dash keep steering the ball once the spikes are out
	if is_dashing:
		_stop_dash()
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

	if is_local_player and _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
		_sync_spiky.rpc(false)

func _try_power(power_name: String, input_x: float) -> void:
	# dispatch whatever ability sits in a mouse-slot to its actual trigger fn
	match power_name:
		"dash":
			_try_dash(input_x)
		"spiky":
			_try_spiky()
		"bomb":
			_try_bomb()

func _try_bomb() -> void:
	# bro grabbed the bomb, check equipped/cooldown/not-already-mid-another-power
	if not equipped_powers.has("bomb"):
		return
	if bomb_cooldown_timer > 0.0 or is_dead or is_holding_bomb or is_spiky:
		return

	is_holding_bomb = true
	bomb_hold_timer = 0.0
	bomb_startup_frames_remaining = BOMB_STARTUP_FRAMES

	# cant be mid dash n suddenly pull a bomb out lol, cancel it clean
	if is_dashing:
		_stop_dash()

	_show_bomb_hold_visual()

	if _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
		_sync_bomb_hold.rpc(true)

@rpc("reliable")
func _sync_bomb_hold(active: bool) -> void:
	# other player started/stopped holding a bomb, mirror the visual on our screen
	if is_local_player:
		return
	if active:
		is_holding_bomb = true
		bomb_hold_timer = 0.0
		bomb_startup_frames_remaining = BOMB_STARTUP_FRAMES
		_show_bomb_hold_visual()
	else:
		is_holding_bomb = false
		_hide_bomb_hold_visual()

func _show_bomb_hold_visual() -> void:
	# lil bomb sprite tucked against the ball while its bein held, matches
	# the ref art. skipped entirely (no crash) if the texture aint in the
	# project yet
	if _bomb_hold_sprite:
		return
	if not ResourceLoader.exists("res://Menu/Bomb.png"):
		return
	var tex := load("res://Menu/Bomb.png") as Texture2D
	if not tex:
		return

	_bomb_hold_sprite = Sprite2D.new()
	_bomb_hold_sprite.texture = tex
	_bomb_hold_sprite.scale = Vector2(BOMB_HOLD_SCALE, BOMB_HOLD_SCALE)
	_bomb_hold_sprite.position = bomb_aim_dir * BOMB_HOLD_RADIUS
	_bomb_hold_sprite.z_index = 3
	add_child(_bomb_hold_sprite)

func _hide_bomb_hold_visual() -> void:
	if _bomb_hold_sprite:
		_bomb_hold_sprite.queue_free()
		_bomb_hold_sprite = null

func _release_bomb() -> void:
	if not is_holding_bomb:
		return

	is_holding_bomb = false
	bomb_cooldown_timer = BOMB_COOLDOWN
	_hide_bomb_hold_visual()

	if _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
		_sync_bomb_hold.rpc(false)

	if is_dead:
		return

	# let go before the startup windup finished? bomb just fumbles outta ur
	# hand instead of a proper throw, gotta wait out the full windup to chuck
	# it at full force
	var throw_speed: float = BOMB_THROW_FORCE if bomb_startup_frames_remaining <= 0 else BOMB_THROW_FORCE * 0.3

	# throw exactly where u were AIMING (the mouse direction the held bomb
	# was already orbiting toward), not the direction u last walked in. those
	# two used to be different vars n it made throws come out backwards
	# whenever u aimed one way after having last moved the other way
	var throw_dir: Vector2 = bomb_aim_dir.normalized() if bomb_aim_dir.length() > 0.01 else Vector2.RIGHT
	var throw_velocity := throw_dir * throw_speed
	var spawn_pos := global_position + throw_dir * BOMB_SPAWN_DISTANCE

	# whatever time was left on the SAME fuse clock that started counting the
	# moment we pulled the bomb out -- holding it a while before throwing
	# means it goes off almost right away once it leaves ur hand, exactly
	# the grenade-timing feel we're going for
	var remaining_fuse: float = max(BOMB_FUSE_TIME - bomb_hold_timer, 0.05)
	var bomb_id := _make_bomb_id()

	_spawn_bomb(spawn_pos, throw_velocity, remaining_fuse, bomb_id)

	if _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
		_spawn_bomb_remote.rpc(spawn_pos, throw_velocity, remaining_fuse, bomb_id)

func _detonate_held_bomb() -> void:
	var blast_position := global_position
	is_holding_bomb = false
	bomb_cooldown_timer = BOMB_COOLDOWN
	_hide_bomb_hold_visual()
	if is_local_player and _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
		_sync_bomb_hold.rpc(false)

	# cook it all the way and let the blast decide who gets caught
	var bomb_id := _make_bomb_id()
	_spawn_bomb(blast_position, Vector2.ZERO, 0.0, bomb_id)
	if _has_network_peer() and not NetworkManagerScript.is_scene_transitioning:
		_spawn_bomb_remote.rpc(blast_position, Vector2.ZERO, 0.0, bomb_id)

func _make_bomb_id() -> String:
	_bomb_sequence += 1
	return "%d:%d:%d" % [player_id, Time.get_ticks_usec(), _bomb_sequence]

func _spawn_bomb(spawn_pos: Vector2, throw_velocity: Vector2, remaining_fuse: float, bomb_id: String) -> void:
	if not BombScene or not get_tree().current_scene:
		return
	var network_mgr = get_node_or_null("/root/NetworkManager")
	if network_mgr and network_mgr.has_resolved_bomb(bomb_id):
		return
	var bomb := BombScene.instantiate()
	get_tree().current_scene.add_child(bomb)
	bomb.explosion_radius = BOMB_EXPLOSION_RADIUS
	bomb.launch(spawn_pos, throw_velocity, player_id, remaining_fuse, bomb_id)

@rpc("reliable")
func _spawn_bomb_remote(spawn_pos: Vector2, throw_velocity: Vector2, remaining_fuse: float, bomb_id: String) -> void:
	# other player threw a bomb, spawn our own local copy of it so everyone
	# sees roughly the same arc n explosion (each client sims it locally,
	# same lightweight-sync approach the rest of the powers use)
	if is_local_player:
		return
	_spawn_bomb(spawn_pos, throw_velocity, remaining_fuse, bomb_id)

func apply_blast_knockback(blast_position: Vector2, knockback_radius: float, force: float) -> void:
	if is_dead or not is_local_player or knockback_radius <= 0.0:
		return
	var away_from_blast := global_position - blast_position
	var distance: float = away_from_blast.length()
	if distance >= knockback_radius:
		return
	if distance <= 0.001:
		away_from_blast = Vector2.UP
	var falloff: float = 1.0 - distance / knockback_radius
	var knockback_direction := away_from_blast.normalized()
	# even a sideways blast gets a lil lift so a close miss actually launches u
	knockback_direction.y = min(knockback_direction.y, -0.55)
	velocity += knockback_direction.normalized() * force * falloff
