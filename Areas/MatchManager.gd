extends Node2D

# so ts handles dropping everyone into the match so we can start fighting I think

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")
const DynamicCameraScript = preload("res://Areas/DynamicCamera.gd")
const GameplayParallaxScript = preload("res://Areas/GameplayParallaxBackground.gd")
const PauseMenuScene: PackedScene = preload("res://Menu/PauseMenu.tscn")

## default spawn pos if you forgot to place marker2d points lol
@export var default_spawn_position: Vector2 = Vector2(576, 300)
## manual spawn coords if u prefer configuring it in inspector
@export var spawn_positions: Array[Vector2] = []
## so the player respawns on death in tutorial for multi step stuff
@export var respawn_on_death: bool = false

var is_tutorial: bool = false

@onready var players_container: Node2D = $Players
@onready var void_zone: Area2D = $VoidZone
@onready var instructions_label: Label = get_node_or_null("HUD/InstructionsLabel")
var player_scene: PackedScene = preload("res://Character/Player.tscn")

const INSTRUCTIONS_HOLD_TIME: float = 4.0 # how long controls prompt stays fully visible I think
const INSTRUCTIONS_FADE_TIME: float = 1.0 # how long it takes to fade out after that

var is_round_over: bool = false
var game_camera: Camera2D
var round_participant_count: int = 0
var _match_end_check_pending: bool = false

func _ready() -> void:
	is_tutorial = scene_file_path.ends_with("Tutorial.tscn")
	if is_tutorial:
		# dummies respawn, so you should too when you're just learning the ropes
		respawn_on_death = true

	# tag ourselves so MobileControls knows ts an actual gameplay scene n not
	# just a menu or smth, thats how it decides whether to show the touch buttons at all
	add_to_group("gameplay_scene")

	spawn_players()
	_setup_camera()
	_setup_background()
	var pause_menu := PauseMenuScene.instantiate()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)

	_show_move_instructions()
	if void_zone:
		void_zone.body_entered.connect(_on_void_zone_body_entered)
	
	# listens for when someone ragequits or loses connection
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.call("report_match_scene_ready")

func _setup_camera() -> void:
	# keeps everyone alive in frame n zooms out when they spread apart
	game_camera = Camera2D.new()
	game_camera.name = "DynamicCamera"
	game_camera.set_script(DynamicCameraScript)
	add_child(game_camera)

func _setup_background() -> void:
	# menus keep the global bg, matches use the camera-aware one in the map
	var old_bg := get_node_or_null("/root/Background")
	if old_bg:
		old_bg.visible = false

	# MapTemplate already owns this node. only make one for older maps that
	# dont have it yet, otherwise every match gets two full backgrounds
	var parallax_bg := get_node_or_null("GameplayBackground")
	if not parallax_bg:
		parallax_bg = Node2D.new()
		parallax_bg.name = "GameplayBackground"
		parallax_bg.set_script(GameplayParallaxScript)
		add_child(parallax_bg)
	move_child(parallax_bg, 0)

func _exit_tree() -> void:
	# turn the menu bg back on when this match goes away
	var old_bg := get_node_or_null("/root/Background")
	if old_bg:
		old_bg.visible = true

func _show_move_instructions() -> void:
	# keep the tutorial cheat sheet around so nobody has to memorize the whole game lol
	if not instructions_label:
		return
	instructions_label.modulate.a = 1.0
	if is_tutorial:
		var mobile_controls = get_node_or_null("/root/MobileControls")
		var touch_mode: bool = mobile_controls != null and mobile_controls.is_mobile_active
		instructions_label.offset_left = 96.0
		instructions_label.offset_right = -20.0
		instructions_label.offset_top = 18.0
		instructions_label.offset_bottom = 228.0
		instructions_label.add_theme_font_size_override("font_size", 16 if touch_mode else 21)
		instructions_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		instructions_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		if touch_mode:
			instructions_label.text = "Move: left joystick     Jump: UP button\nDash: tap Dash for a fast burst\nSpiky: tap Spiky; touch rivals to pop them (3.5s; steering/jump locked)\nBomb: hold Bomb icon; aim with joystick; release to throw (3.5s fuse)\nOnly equipped power buttons show; powers cool down for 2s\nKeyboard if connected: A/D move, W/Space jump, Shift/J Dash, E/F/K Spiky, Q Bomb\nMouse if connected: left/middle/right use slots; move mouse to aim Bomb"
		else:
			instructions_label.text = "Move: A / D or ← / →     Jump: W / Space / ↑\nDash: Shift / J     Spiky: E / F / K (3.5s; touch rivals to pop them)\nSpiky locks steering, jumping and dashing while active\nBomb: hold Q to cook, release to throw (3.5s fuse)\nLeft / Middle / Right click trigger power slots 1 / 2 / 3; 2s cooldowns"
		return

	var tween := create_tween()
	tween.tween_interval(INSTRUCTIONS_HOLD_TIME)
	tween.tween_property(instructions_label, "modulate:a", 0.0, INSTRUCTIONS_FADE_TIME)

func _on_void_zone_body_entered(body: Node2D) -> void:
	# so ts makes like whoever falls in the void just dies instantly wherever they were
	if body.has_method("die"):
		body.die()

func get_spawn_position(index: int) -> Vector2:
	# 1. tries grabbing marker2d nodes under spawnpoints or spawns
	var spawns: Node = get_node_or_null("SpawnPoints")
	if not spawns:
		spawns = get_node_or_null("Spawns")
	if spawns != null and spawns.get_child_count() > 0:
		var child = spawns.get_child(index % spawns.get_child_count())
		if child is Node2D:
			return child.global_position

	# 2. checks for nodes tagged with spawn_point group
	var group_spawns = get_tree().get_nodes_in_group("spawn_point")
	if group_spawns.size() > 0:
		var spawn_node = group_spawns[index % group_spawns.size()]
		if spawn_node is Node2D:
			return spawn_node.global_position

	# 3. falls back to the inspector array
	if spawn_positions.size() > 0:
		return spawn_positions[index % spawn_positions.size()]

	# 4. last resort fallback positions if literally everything else fails ngl
	if scene_file_path == "res://Areas/Tutorial.tscn":
		return Vector2(768, 509)
	if NetworkManagerScript.players.size() > 0:
		return Vector2(250 + (index * 120), 120)
	return default_spawn_position

func spawn_players() -> void:
	if not players_container:
		players_container = get_node_or_null("Players")
		if not players_container:
			players_container = Node2D.new()
			players_container.name = "Players"
			add_child(players_container)

	# clear out old player nodes lying around from last time
	for child in players_container.get_children():
		child.queue_free()
	round_participant_count = 0

	if NetworkManagerScript.players.size() > 0:
		# spawns everyone from the lobby if playing multi
		var spawn_index: int = 0
		for peer_id in NetworkManagerScript.players.keys():
			var p_info: Dictionary = NetworkManagerScript.players[peer_id]
			var player_id: int = int(peer_id)
			var player_name: String = str(p_info.get("name", "Player"))
			var player_color: Color = p_info.get("color", Color.WHITE)
			var powers: Array = p_info.get("powers", ["dash"])
			var player = player_scene.instantiate()
			player.name = str(player_id)
			player.position = get_spawn_position(spawn_index)
			# ready runs inside add_child, so give the player its real ID/loadout
			# first or every new peer briefly looks like host 1 with only Dash.
			player.player_id = player_id
			player.player_display_name = player_name
			player.player_color = player_color
			player.equipped_powers = powers.duplicate()
			players_container.add_child(player)
			player.setup_player(player_id, player_name, player_color, powers)
			player.player_died.connect(_on_player_died)
			round_participant_count += 1
			spawn_index += 1
	else:
		# solo mode testing so the game doesnt crash when u run the scene directly
		var player = player_scene.instantiate()
		player.name = "1"
		player.position = get_spawn_position(0)
		players_container.add_child(player)
		player.setup_player(1, PlayerData.player_name, PlayerData.skin_color, PlayerData.equipped_powers)
		player.player_died.connect(_on_player_died)
		round_participant_count = 1

func _on_player_died(_dead_player_id: int) -> void:
	if is_tutorial:
		var tree := get_tree()
		if not tree:
			return
		await tree.create_timer(1.2).timeout
		if not is_inside_tree():
			return
		if respawn_on_death:
			spawn_players()
		else:
			get_tree().change_scene_to_file("res://Menu/MainMenu.tscn")
		return

	# checks whos still surviving to figure out the winner n go to next level
	if not _match_end_check_pending:
		_match_end_check_pending = true
		call_deferred("_run_match_end_check")

func _run_match_end_check() -> void:
	_match_end_check_pending = false
	_check_match_end()

func _check_match_end() -> void:
	if is_round_over or is_tutorial:
		return

	var alive_players: Array = []
	if players_container:
		for child in players_container.get_children():
			if is_instance_valid(child) and not child.is_queued_for_deletion() and "is_dead" in child and not child.is_dead:
				alive_players.append(child)

	# so ts checks if only 1 guy is left standing to trigger the win screen
	if alive_players.size() == 1 and round_participant_count > 1:
		is_round_over = true
		var winner = alive_players[0]
		var winner_name: String = winner.player_display_name if "player_display_name" in winner else "Player"
		_handle_round_won(winner_name)
	elif alive_players.is_empty() and round_participant_count > 0:
		is_round_over = true
		_handle_round_won("NOBODY")

func _handle_round_won(winner_name: String) -> void:
	_show_winner_banner(winner_name)
	var tree := get_tree()
	if not tree:
		return
	await tree.create_timer(2.2).timeout
	if not is_inside_tree():
		return
	advance_to_next_level()

func advance_to_next_level() -> void:
	var next_path: String = get_next_level_path()
	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if NetworkManagerScript.is_in_room():
		# clients wait for the host's scene rpc so rounds cant drift apart
		if not network_mgr or not NetworkManagerScript.is_host:
			return
		is_round_over = false
		print("Host changing level to: ", next_path)
		# tiny delay so the clients dont get desynced while it loads
		var tree := get_tree()
		if not tree:
			return
		await tree.create_timer(0.1).timeout
		if not is_inside_tree():
			return
		network_mgr.change_level(next_path)
	else:
		is_round_over = false
		get_tree().change_scene_to_file(next_path)

func get_next_level_path() -> String:
	# cycles the grass map rotation, grass1 -> grass2 -> grass3 -> grass4 -> back to grass1
	if scene_file_path.ends_with("Grass1.tscn"):
		return "res://Areas/Grass2.tscn"
	elif scene_file_path.ends_with("Grass2.tscn"):
		return "res://Areas/Grass3.tscn"
	elif scene_file_path.ends_with("Grass3.tscn"):
		return "res://Areas/Grass4.tscn"
	else:
		return "res://Areas/Grass1.tscn"

func _show_winner_banner(winner_name: String) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100

	var banner := Label.new()
	banner.text = "%s WINS!" % winner_name.to_upper() if winner_name != "NOBODY" else "DRAW!"
	banner.add_theme_font_size_override("font_size", 42)
	banner.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	banner.anchors_preset = Control.PRESET_CENTER
	banner.anchor_left = 0.5
	banner.anchor_top = 0.5
	banner.anchor_right = 0.5
	banner.anchor_bottom = 0.5
	banner.offset_left = -300.0
	banner.offset_top = -60.0
	banner.offset_right = 300.0
	banner.offset_bottom = 60.0
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner.pivot_offset = Vector2(300, 60)
	banner.scale = Vector2.ZERO

	canvas.add_child(banner)
	add_child(canvas)

	var tween := create_tween()
	tween.tween_property(banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_player_disconnected(peer_id: int) -> void:
	# removes the disconnected player node instantly so we dont get a ghost body stuck around
	print("MatchManager: Player ", peer_id, " disconnected, removing from scene")
	if not is_instance_valid(players_container):
		players_container = get_node_or_null("Players")
	if not players_container:
		return

	# finds n frees the dc'd player node
	for player in players_container.get_children():
		if is_instance_valid(player) and not player.is_queued_for_deletion() and player.get("player_id") == peer_id:
			print("Removing player node: ", player.name)
			player.queue_free()
			break
	
	# so ts checks if someone bailing mid match means the remaining player just wins
	var tree := get_tree()
	if not tree:
		return
	await tree.create_timer(0.1).timeout
	if not is_inside_tree():
		return
	_check_match_end()
