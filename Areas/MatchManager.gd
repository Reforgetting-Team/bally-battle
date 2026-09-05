extends Node2D

# so ts handles dropping everyone into the match so we can start fighting I think

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")

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

func _ready() -> void:
	is_tutorial = scene_file_path.ends_with("Tutorial.tscn")

	# tag ourselves so MobileControls knows ts an actual gameplay scene n not
	# just a menu or smth, thats how it decides whether to show the touch buttons at all
	add_to_group("gameplay_scene")

	spawn_players()

	_show_move_instructions()
	if void_zone:
		void_zone.body_entered.connect(_on_void_zone_body_entered)
	
	# listens for when someone ragequits or loses connection
	multiplayer.peer_disconnected.connect(_on_player_disconnected)

func _show_move_instructions() -> void:
	# quick how to play text for new players so it fades out n doesnt clutter the screen
	if not instructions_label:
		return
	instructions_label.modulate.a = 1.0
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
	# fresh match reset so dead bodies dont keep stacking up every rematch I think
	var PlayerScript = preload("res://Areas/Player.gd")
	PlayerScript.dead_count = 0

	if not players_container:
		players_container = get_node_or_null("Players")
		if not players_container:
			players_container = Node2D.new()
			players_container.name = "Players"
			add_child(players_container)

	# clear out old player nodes lying around from last time
	for child in players_container.get_children():
		child.queue_free()

	if NetworkManagerScript.players.size() > 0:
		# spawns everyone from the lobby if playing multi
		var spawn_index: int = 0
		for peer_id in NetworkManagerScript.players.keys():
			var p_info = NetworkManagerScript.players[peer_id]
			var player = player_scene.instantiate()
			player.name = str(peer_id)
			player.position = get_spawn_position(spawn_index)
			players_container.add_child(player)
			var powers = p_info.get("powers", ["dash"])
			player.setup_player(peer_id, p_info.get("name", "Player"), p_info.get("color", Color.WHITE), powers)
			player.player_died.connect(_on_player_died)
			spawn_index += 1
	else:
		# solo mode testing so the game doesnt crash when u run the scene directly
		var player = player_scene.instantiate()
		player.name = "1"
		player.position = get_spawn_position(0)
		players_container.add_child(player)
		player.setup_player(1, PlayerData.player_name, PlayerData.skin_color, PlayerData.equipped_powers)
		player.player_died.connect(_on_player_died)

func _on_player_died(_dead_player_id: int) -> void:
	if is_tutorial:
		if respawn_on_death:
			await get_tree().create_timer(1.2).timeout
			spawn_players()
		else:
			await get_tree().create_timer(1.2).timeout
			get_tree().change_scene_to_file("res://Menu/MainMenu.tscn")
		return

	# checks whos still surviving to figure out the winner n go to next level
	_check_match_end()

func _check_match_end() -> void:
	if is_round_over or is_tutorial:
		return

	var alive_players: Array = []
	if players_container:
		for child in players_container.get_children():
			if "is_dead" in child and not child.is_dead:
				alive_players.append(child)

	var total_players: int = players_container.get_child_count() if players_container else 0

	# so ts checks if only 1 guy is left standing to trigger the win screen
	if alive_players.size() == 1 and total_players > 1:
		is_round_over = true
		var winner = alive_players[0]
		var winner_name: String = winner.player_display_name if "player_display_name" in winner else "Player"
		_handle_round_won(winner_name)
	elif alive_players.size() == 0 and total_players > 0:
		is_round_over = true
		_handle_round_won("NOBODY")

func _handle_round_won(winner_name: String) -> void:
	_show_winner_banner(winner_name)
	await get_tree().create_timer(2.2).timeout
	advance_to_next_level()

func advance_to_next_level() -> void:
	# revives everyone for the next round i think
	var PlayerScript = preload("res://Areas/Player.gd")
	PlayerScript.dead_count = 0
	is_round_over = false

	var next_path: String = get_next_level_path()
	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if network_mgr and NetworkManagerScript.is_host and NetworkManagerScript.is_in_room():
		print("Host changing level to: ", next_path)
		# tiny delay so the clients dont get desynced while it loads
		await get_tree().create_timer(0.1).timeout
		network_mgr.change_level(next_path)
	else:
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
	
	# finds n frees the dc'd player node
	for player in players_container.get_children():
		if player.has_method("get") and player.get("player_id") == peer_id:
			print("Removing player node: ", player.name)
			player.queue_free()
			break
	
	# so ts checks if someone bailing mid match means the remaining player just wins
	await get_tree().create_timer(0.1).timeout
	_check_match_end()
