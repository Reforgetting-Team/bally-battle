extends Node2D

# handles dropping everyone into the match so we can start fighting

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")

## Default position where players spawn when no Marker2D spawn points are placed.
@export var default_spawn_position: Vector2 = Vector2(576, 300)
## Optional list of spawn coordinates configured directly in the Inspector.
@export var spawn_positions: Array[Vector2] = []
## If true, player respawns on death in tutorial (for multi-step challenges)
@export var respawn_on_death: bool = false

var is_tutorial: bool = false

@onready var players_container: Node2D = $Players
@onready var void_zone: Area2D = $VoidZone
@onready var instructions_label: Label = get_node_or_null("HUD/InstructionsLabel")
var player_scene: PackedScene = preload("res://Character/Player.tscn")

const INSTRUCTIONS_HOLD_TIME: float = 4.0  # how long the controls prompt stays fully visible
const INSTRUCTIONS_FADE_TIME: float = 1.0  # how long it takes to fade out after that

func _ready() -> void:
	is_tutorial = scene_file_path.ends_with("Tutorial.tscn")
	spawn_players()
	_show_move_instructions()
	if void_zone:
		void_zone.body_entered.connect(_on_void_zone_body_entered)

func _show_move_instructions() -> void:
	# quick "how to play" prompt for new players - shows on load, then fades
	# itself out so it doesn't clutter the screen once you're moving around
	if not instructions_label:
		return
	instructions_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(INSTRUCTIONS_HOLD_TIME)
	tween.tween_property(instructions_label, "modulate:a", 0.0, INSTRUCTIONS_FADE_TIME)

func _on_void_zone_body_entered(body: Node2D) -> void:
	# anyone who falls into the void dies immediately, wherever they were
	if body.has_method("die"):
		body.die()

func get_spawn_position(index: int) -> Vector2:
	# 1. Visual Marker2D / Node2D children under a "SpawnPoints" or "Spawns" node
	var spawns: Node = get_node_or_null("SpawnPoints")
	if not spawns:
		spawns = get_node_or_null("Spawns")
	if spawns != null and spawns.get_child_count() > 0:
		var child = spawns.get_child(index % spawns.get_child_count())
		if child is Node2D:
			return child.global_position

	# 2. Any node in the scene tagged with group "spawn_point"
	var group_spawns = get_tree().get_nodes_in_group("spawn_point")
	if group_spawns.size() > 0:
		var spawn_node = group_spawns[index % group_spawns.size()]
		if spawn_node is Node2D:
			return spawn_node.global_position

	# 3. Direct inspector coordinate array
	if spawn_positions.size() > 0:
		return spawn_positions[index % spawn_positions.size()]

	# 4. Fallback defaults (tutorial specific position if on tutorial, else default_spawn_position)
	if scene_file_path == "res://Areas/Tutorial.tscn":
		return Vector2(768, 509)
	if NetworkManagerScript.players.size() > 0:
		return Vector2(250 + (index * 120), 120)
	return default_spawn_position

func spawn_players() -> void:
	# fresh match, fresh death corner - otherwise a rematch would keep stacking
	# dead players further and further left/down from last game
	var PlayerScript = preload("res://Areas/Player.gd")
	PlayerScript.dead_count = 0

	if not players_container:
		players_container = get_node_or_null("Players")
		if not players_container:
			players_container = Node2D.new()
			players_container.name = "Players"
			add_child(players_container)

	# clear whatever old balls were lying around
	for child in players_container.get_children():
		child.queue_free()

	if NetworkManagerScript.players.size() > 0:
		# spawn everyone from the lobby
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
		# solo mode / testing without friends
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

	# match mode: check surviving players to declare the winner and progress to next level
	if is_round_over:
		return

	var alive_players: Array = []
	if players_container:
		for child in players_container.get_children():
			if "is_dead" in child and not child.is_dead:
				alive_players.append(child)

	var total_players: int = players_container.get_child_count() if players_container else 0

	# When only 1 person remains alive (or if someone dies in solo testing)
	if alive_players.size() == 1 and total_players > 1:
		is_round_over = true
		var winner = alive_players[0]
		var winner_name: String = winner.player_display_name if "player_display_name" in winner else "Player"
		_handle_round_won(winner_name)
	elif alive_players.size() == 0 and total_players > 0:
		is_round_over = true
		_handle_round_won("NOBODY")

var is_round_over: bool = false

func _handle_round_won(winner_name: String) -> void:
	_show_winner_banner(winner_name)
	await get_tree().create_timer(2.2).timeout
	advance_to_next_level()

func advance_to_next_level() -> void:
	# revives everybody for the next round
	var PlayerScript = preload("res://Areas/Player.gd")
	PlayerScript.dead_count = 0
	is_round_over = false

	var next_path: String = get_next_level_path()
	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if network_mgr and NetworkManagerScript.is_host and NetworkManagerScript.is_in_room():
		network_mgr.change_level(next_path)
	else:
		get_tree().change_scene_to_file(next_path)

func get_next_level_path() -> String:
	# cycles through Grass1 -> Grass2 -> Grass3 -> Grass1
	if scene_file_path.ends_with("Grass1.tscn"):
		return "res://Areas/Grass2.tscn"
	elif scene_file_path.ends_with("Grass2.tscn"):
		return "res://Areas/Grass3.tscn"
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
