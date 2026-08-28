extends Node2D

# handles dropping everyone into the match so we can start fighting

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")

@onready var players_container: Node2D = $Players
var player_scene: PackedScene = preload("res://Character/Player.tscn")

func _ready() -> void:
	spawn_players()

func spawn_players() -> void:
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
			# spawn them floating up in the air so they drop and bounce on the floor
			player.position = Vector2(250 + (spawn_index * 120), 120)
			players_container.add_child(player)
			player.setup_player(peer_id, p_info.get("name", "Player"), p_info.get("color", Color.WHITE))
			spawn_index += 1
	else:
		# solo mode / testing without friends
		var player = player_scene.instantiate()
		player.name = "1"
		# drop in from the sky
		player.position = Vector2(552, 120)
		players_container.add_child(player)
		player.setup_player(1, PlayerData.player_name, PlayerData.skin_color)
