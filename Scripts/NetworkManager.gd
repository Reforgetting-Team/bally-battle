extends Node

# ts manages all the multiplayer p2p stuff n keeps everyone connected

const DEFAULT_PORT: int = 8910
const DEFAULT_IP: String = "127.0.0.1"

# holding the boys info so we know who is who n what color they picked
static var players: Dictionary = {}
static var is_host: bool = false
static var peer: ENetMultiplayerPeer = null
static var instance: Node = null

signal player_list_changed
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal match_started

func _enter_tree() -> void:
	instance = self

func _ready() -> void:
	instance = self
	# hook up all the networking signal garbage
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

static func is_in_room() -> bool:
	return peer != null

static func can_start_match() -> bool:
	# cant start if ur alone unless debug mode's on, or someone's still
	# messing around with their colors/powers n not ready yet
	if not is_host:
		return false
	if not PlayerData.debug_mode and players.size() < 2:
		return false
	for p in players.values():
		if not p.get("ready", true):
			return false
	return true

static func get_bindable_addresses() -> PackedStringArray:
	# only real local interface addresses can get passed to set_bind_ip,
	# anything else (like a friend's IP, a router IP, an inactive ZeroTier
	# adapter) just fails w ERR_CANT_CREATE (20) n confuses everyone
	var result := PackedStringArray()
	for addr in IP.get_local_addresses():
		if not addr.is_empty():
			result.append(addr)
	return result

func create_game(bind_address: String = "", port: int = DEFAULT_PORT) -> Error:
	# reset whatever was going on before n host a fresh new room
	var clean_bind = bind_address.strip_edges()
	if not clean_bind.is_empty() and not get_bindable_addresses().has(clean_bind):
		push_error("%s is not one of this machine's local addresses: %s" % [clean_bind, get_bindable_addresses()])
		return ERR_INVALID_PARAMETER

	leave_game()
	peer = ENetMultiplayerPeer.new()
	var host = ENetMultiplayerPeer.new()
	if not clean_bind.is_empty():
		host.set_bind_ip(clean_bind)
	var host_err = host.create_server(port, 32, 0, 0, 0)
	if host_err != OK:
		push_error("Failed to start server on %s:%d: %s" % [clean_bind, port, host_err])
		return host_err
	bind_address = clean_bind

	peer = host
	multiplayer.multiplayer_peer = peer
	is_host = true
	# add the host in as player 1
	players[1] = {
		"name": PlayerData.player_name,
		"color": PlayerData.skin_color,
		"powers": PlayerData.equipped_powers.duplicate(),
		"ready": true
	}
	player_list_changed.emit()
	print("Server started on ", bind_address, ":", port)
	return OK

func join_game(address: String = DEFAULT_IP, port: int = DEFAULT_PORT) -> Error:
	# connect to ur friend's zerotier ip or just localhost for testing solo
	leave_game()
	var target_ip = address.strip_edges()
	if target_ip.is_empty():
		target_ip = DEFAULT_IP

	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(target_ip, port)
	if err != OK:
		push_error("Failed to create client connecting to %s:%d: %s" % [target_ip, port, err])
		return err

	multiplayer.multiplayer_peer = peer
	is_host = false
	print("Connecting to ", target_ip, ":", port)
	return OK

func leave_game() -> void:
	# nuke the connection n clean up literally everything
	if peer != null:
		peer.close()
		peer = null
	if multiplayer:
		multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	player_list_changed.emit()

func update_player_info(new_name: String, new_color: Color, new_powers: Array = []) -> void:
	# so ts sends our updated name/color/powers to the host so everyone else
	# gets it syncronizated n sees the change too
	if peer == null:
		return
	if is_host:
		if players.has(1):
			players[1]["name"] = new_name
			players[1]["color"] = new_color
			if new_powers.size() > 0:
				players[1]["powers"] = new_powers
			_sync_players.rpc(players)
			player_list_changed.emit()
	else:
		_update_player_info_rpc.rpc_id(1, new_name, new_color, new_powers)

func set_player_ready(is_ready: bool) -> void:
	# tell the host whether were just chillin in lobby or off customizing our ball rn
	if peer == null:
		return
	if is_host:
		if players.has(1):
			players[1]["ready"] = is_ready
			_sync_players.rpc(players)
			player_list_changed.emit()
	else:
		_set_player_ready_rpc.rpc_id(1, is_ready)

@rpc("any_peer", "reliable")
func _update_player_info_rpc(new_name: String, new_color: Color, new_powers: Array = []) -> void:
	# host gets the updated info from a client n fans it back out to the whole class
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if players.has(sender_id):
		players[sender_id]["name"] = new_name
		players[sender_id]["color"] = new_color
		if new_powers.size() > 0:
			players[sender_id]["powers"] = new_powers
		_sync_players.rpc(players)
		player_list_changed.emit()

@rpc("any_peer", "reliable")
func _set_player_ready_rpc(is_ready: bool) -> void:
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if players.has(sender_id):
		players[sender_id]["ready"] = is_ready
		_sync_players.rpc(players)
		player_list_changed.emit()

func _on_connected_to_server() -> void:
	# we in! tell the host who we are so it can add us to the roster
	var my_id = multiplayer.get_unique_id()
	print("Connected to server! Local peer ID: ", my_id)
	var my_info = {
		"name": PlayerData.player_name,
		"color": PlayerData.skin_color,
		"powers": PlayerData.equipped_powers.duplicate(),
		"ready": true
	}
	_register_player.rpc_id(1, my_info)
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("Connection to server failed.")
	leave_game()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("Server disconnected.")
	leave_game()
	server_disconnected.emit()
	get_tree().change_scene_to_file("res://Menu/Lobby.tscn")

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if is_host:
		players.erase(id)
		_sync_players.rpc(players)
		player_list_changed.emit()

@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	# host registers the newcomer n blasts the updated player list out to everybody
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	players[sender_id] = info
	print("Registered peer %d: %s" % [sender_id, info])
	_sync_players.rpc(players)
	player_list_changed.emit()

@rpc("authority", "reliable")
func _sync_players(updated_players: Dictionary) -> void:
	# so ts is where the client actually receives the latest syncronizated player roster
	players = updated_players
	player_list_changed.emit()

func start_game(scene_path: String = "res://Areas/Grass1.tscn") -> void:
	if not is_host:
		return
	if not can_start_match():
		return
	_load_match_scene.rpc(scene_path)

func change_level(scene_path: String) -> void:
	# transitions everybody connected over to the next level in between rounds
	if not is_host:
		return
	_load_match_scene.rpc(scene_path)

@rpc("authority", "call_local", "reliable")
func _load_match_scene(scene_path: String) -> void:
	# tell everyone in the lobby to load into the arena at the same time
	print("Loading scene: ", scene_path, " (is_host: ", is_host, ", peer_id: ", multiplayer.get_unique_id(), ")")
	match_started.emit()
	get_tree().change_scene_to_file(scene_path)
