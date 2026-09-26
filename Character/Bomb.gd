extends CharacterBody2D

# so ts bounces off the stage like bopl's grenade, then pops on a hit or when the fuse runs out

signal exploded(explosion_position: Vector2)

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")
const ExplosionScript = preload("res://Character/Explosion.gd")
const BOUNCE_STREAM: AudioStream = preload("res://Sounds/Tongue.ogg")

@export var explosion_radius: float = 90.0

# keep it the same size before n after the throw
const VISUAL_SCALE: float = 0.17
const BOMB_RADIUS: float = 18.0 # matches the CollisionShape2D's circle radius, used for rolling rotation

# so ts makes the bomb bounce off walls n floors instead of just dying on impact,
# cuz thats what makes bopl's grenade fun -- u bank it off a wall onto some guy
const BOUNCE_FACTOR: float = 0.52     # how much speed it keeps per bounce
const MIN_BOUNCE_SPEED: float = 55.0  # slower than ts n it just settles instead of micro-bouncing forever
const BOUNCE_PITCH_SCALE: float = 1.45 # lighter lil bomb, so its thud sounds higher than bally

# let grounded bombs roll to a natural stop
const GROUND_FRICTION: float = 260.0
const ROLL_STOP_SPEED: float = 4.0

# short grace period so the bomb doesnt hit its owner the instant it spawns
const OWNER_IMMUNITY_TIME: float = 0.35
var owner_immunity_timer: float = 0.0

# the blast kills inside explosion_radius n just shoves everyone in ts bigger
# ring, so near misses still yeet u around instead of doing literally nothing
const KNOCKBACK_RADIUS_SCALE: float = 2.5
const KNOCKBACK_FORCE: float = 1300.0

var owner_player_id: int = -1
var bomb_id: String = ""
var has_landed: bool = false

# the fuse starts in Player.gd n never resets, so a late throw pops sooner
var fuse_timer: float = 0.0
var _exploded: bool = false
var _awaiting_authority: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var player_hitbox: Area2D = get_node_or_null("PlayerHitbox")
@onready var bounce_audio: AudioStreamPlayer = $BounceAudio

func _ready() -> void:
	add_to_group("bomb")
	if player_hitbox:
		player_hitbox.body_entered.connect(_on_player_body_entered)

	# grab the bomb art at runtime instead of preloading it so the project
	# doesnt straight up refuse to boot if that texture aint in the project yet
	if ResourceLoader.exists("res://Menu/Bomb.png"):
		var tex := load("res://Menu/Bomb.png") as Texture2D
		if tex and sprite:
			sprite.texture = tex

	if sprite:
		sprite.scale = Vector2(VISUAL_SCALE, VISUAL_SCALE)
	if bounce_audio:
		bounce_audio.stream = BOUNCE_STREAM
		bounce_audio.pitch_scale = BOUNCE_PITCH_SCALE

func launch(from_position: Vector2, throw_velocity: Vector2, thrower_id: int, remaining_fuse: float, identifier: String = "") -> void:
	global_position = from_position
	velocity = throw_velocity
	owner_player_id = thrower_id
	owner_immunity_timer = OWNER_IMMUNITY_TIME
	bomb_id = identifier
	has_landed = false
	fuse_timer = remaining_fuse

func _physics_process(delta: float) -> void:
	if _exploded or _awaiting_authority:
		return

	if owner_immunity_timer > 0.0:
		owner_immunity_timer = max(owner_immunity_timer - delta, 0.0)

	# keep ticking in the air or on the floor, no free fuse reset on landing
	fuse_timer -= delta
	if fuse_timer <= 0.0:
		_explode()
		return

	_update_fuse_flash()

	var gravity: Vector2 = get_gravity()

	if not is_on_floor():
		velocity += gravity * delta
	else:
		# once its resting, roll to a stop w/ friction, purely cosmetic now
		# (the fuse doesnt care whether its landed, only the roll-visual does)
		if not has_landed:
			has_landed = true

		if abs(velocity.x) > ROLL_STOP_SPEED:
			velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
		else:
			velocity.x = 0.0

	# remember the speed BEFORE the move so we can reflect it off whatever we hit,
	# same trick Player.gd pulls for its ball bounces
	var pre_move_velocity: Vector2 = velocity

	move_and_slide()

	_bounce_off_last_collision(pre_move_velocity)
	_check_player_contacts()

	# spin the sprite while it moves, same rolling-ball detail Player.gd does
	if abs(velocity.x) > 0.01:
		sprite.rotation += (velocity.x * delta) / BOMB_RADIUS

func _on_player_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if owner_immunity_timer > 0.0 and body.get("player_id") == owner_player_id:
		return
	_explode()

func _check_player_contacts() -> void:
	if not player_hitbox or owner_immunity_timer > 0.0:
		return
	for body in player_hitbox.get_overlapping_bodies():
		if body.is_in_group("player"):
			_explode()
			return

func _bounce_off_last_collision(pre_move_velocity: Vector2) -> void:
	# ts is the bouncy bit: grab whatever surface we just smacked into n mirror
	# our old velocity off its normal, so a bomb thrown at a wall comes back at u
	if get_slide_collision_count() == 0:
		return
	for collision_index in range(get_slide_collision_count()):
		var slide_hit := get_slide_collision(collision_index)
		var other_body := slide_hit.get_collider()
		if other_body is Node2D and other_body.is_in_group("bomb"):
			# so ts chains the blast when bombs smack into each other, instead of
			# both turning into lil frozen bowling balls lol
			_explode()
			if other_body.has_method("_explode"):
				other_body.call("_explode")
			return

	var collision := get_last_slide_collision()
	if collision == null:
		return

	var normal: Vector2 = collision.get_normal()
	# how hard we went INTO that surface, a graze shouldnt bounce like a slam
	var impact_speed: float = -pre_move_velocity.dot(normal)
	if impact_speed <= MIN_BOUNCE_SPEED:
		return

	if normal.dot(Vector2.UP) > 0.5:
		_play_bounce_sound()
	velocity = pre_move_velocity.bounce(normal) * BOUNCE_FACTOR

func _play_bounce_sound() -> void:
	if bounce_audio:
		bounce_audio.play()

func _update_fuse_flash() -> void:
	# blinks faster the closer it is to popping so u get a heads up to run lol
	if not sprite:
		return
	if fuse_timer > 0.6:
		sprite.modulate = Color.WHITE
		return

	var blink_rate: float = lerp(16.0, 5.0, clamp(fuse_timer / 0.6, 0.0, 1.0))
	var on: bool = fmod(fuse_timer * blink_rate, 2.0) < 1.0
	sprite.modulate = Color(1.6, 0.6, 0.6) if on else Color.WHITE

func _explode() -> void:
	if _exploded or _awaiting_authority:
		return

	# clients let the host call the boom so the whole lobby gets one result
	if _is_networked() and not NetworkManagerScript.is_host:
		var network_mgr = get_node_or_null("/root/NetworkManager")
		if network_mgr and not bomb_id.is_empty():
			_awaiting_authority = true
			velocity = Vector2.ZERO
			set_physics_process(false)
			network_mgr.request_bomb_detonation(bomb_id)
			return

	_exploded = true
	exploded.emit(global_position)

	# who actually dies is decided in ONE place: offline thats just us, online
	# thats the host. every client used to run its own kill check which meant
	# two players could straight up disagree on whether somebody survived
	if not _is_networked():
		_spawn_explosion_visual()
		_resolve_blast_locally()
	elif NetworkManagerScript.is_host:
		var network_mgr := get_node_or_null("/root/NetworkManager")
		if network_mgr:
			network_mgr.broadcast_blast(global_position, explosion_radius, _find_victim_ids(), bomb_id)
		else:
			_spawn_explosion_visual()
			_resolve_blast_locally()

	queue_free()

func _is_networked() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	var active_peer := multiplayer.multiplayer_peer
	return active_peer != null and not (active_peer is OfflineMultiplayerPeer)

func _spawn_explosion_visual() -> void:
	# every client draws its own boom, thats just cosmetic so it doesnt need syncing
	var scene_root := get_tree().current_scene
	if not scene_root:
		return

	var explosion := Node2D.new()
	explosion.set_script(ExplosionScript)
	explosion.radius = explosion_radius
	scene_root.add_child(explosion)
	explosion.global_position = global_position

func _find_victim_ids() -> PackedInt32Array:
	# once it pops, everybody in range is fair game, including the thrower
	var victims := PackedInt32Array()
	for player in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(player) or player.is_queued_for_deletion():
			continue
		if "is_dead" in player and player.is_dead:
			continue
		if player.global_position.distance_to(global_position) <= explosion_radius:
			if "player_id" in player:
				victims.append(player.player_id)
	return victims

func _resolve_blast_locally() -> void:
	# solo / no network: just do the kills n shoves right here
	for player in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(player) or player.is_queued_for_deletion():
			continue
		if "is_dead" in player and player.is_dead:
			continue

		var distance: float = player.global_position.distance_to(global_position)
		if distance <= explosion_radius:
			if player.has_method("die"):
				player.die()
		elif distance <= explosion_radius * KNOCKBACK_RADIUS_SCALE:
			if player.has_method("apply_blast_knockback"):
				player.apply_blast_knockback(global_position, explosion_radius * KNOCKBACK_RADIUS_SCALE, KNOCKBACK_FORCE)
