extends Node

# ts manages all the multiplayer p2p stuff and keeps everyone connected

const DEFAULT_PORT: int = 8910
const DEFAULT_IP: String = "127.0.0.1"

# holding the boys info so we know who is who and what color they picked
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
	# cant start if youre alone or someone is still messing with their colors
	if not is_host or players.is_empty():
		return false
	for p in players.values():
		if not p.get("ready", true):
			return false
	return true

static func get_bindable_addresses() -> PackedStringArray:
	# only real local interface addresses can be passed to set_bind_ip;
	# anything else (a friend's IP, a router IP, an inactive ZeroTier
	# adapter) fails with ERR_CANT_CREATE (20)
	var result := PackedStringArray()
	for addr in IP.get_local_addresses():
		if not addr.is_empty():
			result.append(addr)
	return result

func create_game(bind_address: String = "", port: int = DEFAULT_PORT) -> Error:
	# reset whatever was going on before and host a new room
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
	# add host as player 1
	players[1] = {
		"name": PlayerData.player_name,
		"color": PlayerData.skin_color,
		"ready": true
	}
	player_list_changed.emit()
	print("Server started on ", bind_address, ":", port)
	return OK

func join_game(address: String = DEFAULT_IP, port: int = DEFAULT_PORT) -> Error:
	# connect to your friends zerotier ip or localhost
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
	# nuke connection and clean up everything
	if peer != null:
		peer.close()
		peer = null
	if multiplayer:
		multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	player_list_changed.emit()

func update_player_info(new_name: String, new_color: Color) -> void:
	# send our updated name/color to the host so everyone sees it
	if peer == null:
		return
	var my_id = multiplayer.get_unique_id() if not is_host else 1
	if is_host:
		if players.has(1):
			players[1]["name"] = new_name
			players[1]["color"] = new_color
			_sync_players.rpc(players)
			player_list_changed.emit()
	else:
		_update_player_info_rpc.rpc_id(1, new_name, new_color)

func set_player_ready(is_ready: bool) -> void:
	# tell host if we are chilling in lobby or customizing our ball
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
func _update_player_info_rpc(new_name: String, new_color: Color) -> void:
	# host receives updated info from a client and shares it with the class
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if players.has(sender_id):
		players[sender_id]["name"] = new_name
		players[sender_id]["color"] = new_color
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
	# we joined! tell the host who we are
	var my_id = multiplayer.get_unique_id()
	print("Connected to server! Local peer ID: ", my_id)
	var my_info = {
		"name": PlayerData.player_name,
		"color": PlayerData.skin_color,
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
	# host registers newcomer and blasts player list to everyone
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	players[sender_id] = info
	print("Registered peer %d: %s" % [sender_id, info])
	_sync_players.rpc(players)
	player_list_changed.emit()

@rpc("authority", "reliable")
func _sync_players(updated_players: Dictionary) -> void:
	# client receives latest player roster
	players = updated_players
	player_list_changed.emit()

func start_game(scene_path: String = "res://Areas/Tutorial.tscn") -> void:
	if not is_host:
		return
	if not can_start_match():
		return
	_load_match_scene.rpc(scene_path)

@rpc("authority", "call_local", "reliable")
func _load_match_scene(scene_path: String) -> void:
	# tell everyone in the lobby to load into the arena
	match_started.emit()
	get_tree().change_scene_to_file(scene_path)
