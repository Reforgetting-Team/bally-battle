extends Node

# ts manages all the multiplayer p2p stuff n keeps everyone connected

const DEFAULT_PORT: int = 8910
const DEFAULT_IP: String = "127.0.0.1"
const LAN_DISCOVERY_PORT: int = 8911
const LAN_ADVERTISEMENT_INTERVAL: float = 1.0
const LAN_ROOM_TIMEOUT_MSEC: int = 3500
const LAN_PROTOCOL: String = "bally_battle_lan_v1"
const MAX_PLAYER_NAME_LENGTH: int = 20
const MAX_EQUIPPED_POWERS: int = 3
const VALID_POWERS: PackedStringArray = ["dash", "spiky", "bomb"]
const BLAST_KNOCKBACK_RADIUS_SCALE: float = 2.5
const BLAST_KNOCKBACK_FORCE: float = 1300.0
const ExplosionScript = preload("res://Character/Explosion.gd")

# holding the boys info so we know who is who n what color they picked
static var players: Dictionary = {}
static var is_host: bool = false
static var is_scene_transitioning: bool = false
static var peer: MultiplayerPeer = null
static var instance: Node = null
static var resolved_bomb_expiries: Dictionary = {}
static var is_dedicated_server: bool = false
static var current_room_code: String = ""
static var room_host_peer_id: int = 1
var _idle_server_time: float = 0.0
const DEDICATED_IDLE_TIMEOUT: float = 300.0
var _pending_player_deaths: Dictionary = {}
var _death_batch_scheduled: bool = false
var _scene_transition_id: int = 0
var _scene_ready_peers: Dictionary = {}
var _scene_transition_finish_sent: bool = false
var _lan_socket: PacketPeerUDP = PacketPeerUDP.new()
var _lan_socket_ready: bool = false
var _lan_advertisement_timer: float = 0.0
var _lan_rooms: Dictionary = {}
var is_match_active: bool = false
var hosted_port: int = DEFAULT_PORT

signal player_list_changed
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal match_started
signal lan_rooms_changed
signal room_info_updated(code: String, host_id: int)

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
	_check_cli_args()
	if not is_dedicated_server:
		_start_lan_discovery()

func _check_cli_args() -> void:
	# check if we were booted up as a dedicated headless room server on the vps
	var args := OS.get_cmdline_user_args()
	var is_room_server := false
	var room_code := ""
	var port := DEFAULT_PORT
	
	for i in range(args.size()):
		var arg := args[i]
		if arg == "--room-server" or arg == "--server":
			is_room_server = true
		elif arg == "--code" and i + 1 < args.size():
			room_code = args[i + 1]
		elif arg == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	
	if is_room_server:
		print("[BallyServer] Booting dedicated headless room server for code '%s' on port %d" % [room_code, port])
		create_dedicated_room_server(room_code, port)

func _process(delta: float) -> void:
	if is_dedicated_server:
		if players.is_empty() and not is_scene_transitioning:
			_idle_server_time += delta
			if _idle_server_time >= DEDICATED_IDLE_TIMEOUT:
				print("[BallyServer] Room %s idle for %.1fs, shutting down cleanly" % [current_room_code, _idle_server_time])
				get_tree().quit()
		else:
			_idle_server_time = 0.0

	if not _lan_socket_ready:
		return
	_poll_lan_rooms()
	_expire_lan_rooms()

	if not is_host or peer == null or is_match_active:
		return
	_lan_advertisement_timer -= delta
	if _lan_advertisement_timer <= 0.0:
		_broadcast_lan_room()
		_lan_advertisement_timer = LAN_ADVERTISEMENT_INTERVAL

func _start_lan_discovery() -> void:
	var bind_error: Error = _lan_socket.bind(LAN_DISCOVERY_PORT, "*")
	if bind_error != OK:
		push_warning("LAN room discovery could not bind UDP port %d (error %d)" % [LAN_DISCOVERY_PORT, bind_error])
		return
	_lan_socket.set_broadcast_enabled(true)
	_lan_socket_ready = true

func _broadcast_lan_room() -> void:
	var room_packet := {
		"protocol": LAN_PROTOCOL,
		"port": hosted_port,
		"name": PlayerData.player_name,
		"players": players.size(),
		"capacity": 32
	}
	_lan_socket.set_dest_address("255.255.255.255", LAN_DISCOVERY_PORT)
	var send_error: Error = _lan_socket.put_packet(JSON.stringify(room_packet).to_utf8_buffer())
	if send_error != OK:
		push_warning("LAN room advertisement failed (error %d)" % send_error)

func _poll_lan_rooms() -> void:
	while _lan_socket.get_available_packet_count() > 0:
		var packet_bytes: PackedByteArray = _lan_socket.get_packet()
		var sender_ip: String = _lan_socket.get_packet_ip()
		var packet_data: Variant = JSON.parse_string(packet_bytes.get_string_from_utf8())
		if not (packet_data is Dictionary):
			continue
		if packet_data.get("protocol", "") != LAN_PROTOCOL:
			continue
		if sender_ip.is_empty() or get_bindable_addresses().has(sender_ip):
			continue

		var room_port: int = int(packet_data.get("port", 0))
		if room_port < 1 or room_port > 65535:
			continue
		var room_name: String = str(packet_data.get("name", "Player")).strip_edges()
		room_name = room_name.replace("\n", " ").replace("\r", " ").left(MAX_PLAYER_NAME_LENGTH)
		if room_name.is_empty():
			room_name = "Player"
		var player_count: int = clampi(int(packet_data.get("players", 1)), 1, 32)
		var room_key: String = "%s:%d" % [sender_ip, room_port]
		var changed := true
		if _lan_rooms.has(room_key):
			var previous_room: Dictionary = _lan_rooms[room_key]
			changed = previous_room.get("name", "") != room_name or previous_room.get("players", 0) != player_count
		_lan_rooms[room_key] = {
			"ip": sender_ip,
			"port": room_port,
			"name": room_name,
			"players": player_count,
			"capacity": clampi(int(packet_data.get("capacity", 32)), 1, 32),
			"last_seen": Time.get_ticks_msec()
		}
		if changed:
			lan_rooms_changed.emit()

func _expire_lan_rooms() -> void:
	var now_msec: int = Time.get_ticks_msec()
	var removed_room := false
	for room_key in _lan_rooms.keys():
		var room: Dictionary = _lan_rooms[room_key]
		if now_msec - int(room.get("last_seen", 0)) > LAN_ROOM_TIMEOUT_MSEC:
			_lan_rooms.erase(room_key)
			removed_room = true
	if removed_room:
		lan_rooms_changed.emit()

func get_lan_rooms() -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	var room_keys: Array = _lan_rooms.keys()
	room_keys.sort()
	for room_key in room_keys:
		var room: Dictionary = _lan_rooms[room_key]
		rooms.append(room.duplicate())
	return rooms

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

static func can_room_host_start() -> bool:
	# check if the room host on the client side has the green light to press Start Match
	if not is_in_room():
		return false
	if is_host and not is_dedicated_server:
		return can_start_match()
	if not PlayerData.is_room_host:
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
	var host = ENetMultiplayerPeer.new()
	if not clean_bind.is_empty():
		host.set_bind_ip(clean_bind)
	var host_err = host.create_server(port, 32, 0, 0, 0)
	if host_err != OK:
		push_error("Failed to start server on %s:%d: %s" % [clean_bind, port, host_err])
		host.close()
		return host_err
	bind_address = clean_bind

	peer = host
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_match_active = false
	hosted_port = port
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

func create_dedicated_room_server(room_code: String, port: int) -> Error:
	# so ts spins up the headless room on the vps so anyone w the code can connect
	leave_game()
	var ws := WebSocketMultiplayerPeer.new()
	var err = ws.create_server(port, "0.0.0.0")
	if err != OK:
		push_error("Failed to start dedicated WebSocket room server on port %d: %s" % [port, err])
		ws.close()
		return err

	peer = ws
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_dedicated_server = true
	current_room_code = room_code
	room_host_peer_id = -1
	hosted_port = port
	is_match_active = false
	players.clear()
	print("[BallyServer] Dedicated room server ready for room '%s' on port %d" % [room_code, port])
	return OK

func join_game(address: String = DEFAULT_IP, port: int = DEFAULT_PORT) -> Error:
	# connect to ur friend's zerotier ip, a websocket tunnel or just localhost for testing solo
	leave_game()
	var target_ip = address.strip_edges()
	if target_ip.is_empty():
		target_ip = DEFAULT_IP

	if target_ip.begins_with("ws://") or target_ip.begins_with("wss://"):
		var ws := WebSocketMultiplayerPeer.new()
		var err = ws.create_client(target_ip)
		if err != OK:
			push_error("Failed to connect websocket client to %s: %s" % [target_ip, err])
			ws.close()
			return err
		peer = ws
		multiplayer.multiplayer_peer = peer
		is_host = false
		print("Connecting via WebSocket to ", target_ip)
		return OK
	else:
		var client := ENetMultiplayerPeer.new()
		var err = client.create_client(target_ip, port)
		if err != OK:
			push_error("Failed to create client connecting to %s:%d: %s" % [target_ip, port, err])
			client.close()
			return err
		peer = client
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
	resolved_bomb_expiries.clear()
	is_host = false
	is_dedicated_server = false
	current_room_code = ""
	room_host_peer_id = 1
	PlayerData.current_room_code = ""
	PlayerData.is_room_host = false
	is_scene_transitioning = false
	_scene_transition_id = 0
	_scene_ready_peers.clear()
	_scene_transition_finish_sent = false
	is_match_active = false
	hosted_port = DEFAULT_PORT
	player_list_changed.emit()

func update_player_info(new_name: String, new_color: Color, new_powers: Array = []) -> void:
	# so ts sends our updated name/color/powers to the host so everyone else
	# gets it syncronizated n sees the change too
	if peer == null:
		return
	if is_host:
		if players.has(1):
			var safe_info := _sanitize_player_info({"name": new_name, "color": new_color, "powers": new_powers})
			players[1]["name"] = safe_info["name"]
			players[1]["color"] = safe_info["color"]
			if new_powers.size() > 0:
				players[1]["powers"] = safe_info["powers"]
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
		var safe_info := _sanitize_player_info({"name": new_name, "color": new_color, "powers": new_powers})
		players[sender_id]["name"] = safe_info["name"]
		players[sender_id]["color"] = safe_info["color"]
		if new_powers.size() > 0:
			players[sender_id]["powers"] = safe_info["powers"]
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
	if get_tree().current_scene:
		var curr_path = get_tree().current_scene.scene_file_path
		if curr_path != "res://Menu/RoomSelect.tscn" and curr_path != "res://Menu/Lobby.tscn" and curr_path != "res://Menu/RoomLobby.tscn":
			get_tree().change_scene_to_file("res://Menu/RoomSelect.tscn")

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if is_host:
		players.erase(id)
		if is_dedicated_server and room_host_peer_id == id:
			if not players.is_empty():
				room_host_peer_id = int(players.keys()[0])
				_sync_room_info.rpc(current_room_code, room_host_peer_id)
			else:
				room_host_peer_id = -1
		_sync_players.rpc(players)
		player_list_changed.emit()
		if is_scene_transitioning:
			call_deferred("_try_finish_match_scene_transition")

@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	# host registers the newcomer n blasts the updated player list out to everybody
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id <= 1 and not is_dedicated_server:
		return
	players[sender_id] = _sanitize_player_info(info)
	print("Registered peer %d: %s" % [sender_id, players[sender_id]])
	if is_dedicated_server:
		if room_host_peer_id == -1:
			room_host_peer_id = sender_id
		_sync_room_info.rpc(current_room_code, room_host_peer_id)
	_sync_players.rpc(players)
	player_list_changed.emit()

@rpc("authority", "call_local", "reliable")
func _sync_room_info(code: String, host_id: int) -> void:
	current_room_code = code
	room_host_peer_id = host_id
	PlayerData.current_room_code = code
	PlayerData.is_room_host = (multiplayer.get_unique_id() == host_id)
	room_info_updated.emit(code, host_id)

func request_start_room_match(scene_path: String = "res://Areas/Grass1.tscn") -> void:
	if peer == null:
		return
	if is_host and not is_dedicated_server:
		start_game(scene_path)
	else:
		_request_start_room_match_rpc.rpc_id(1, scene_path)

@rpc("any_peer", "reliable")
func _request_start_room_match_rpc(scene_path: String) -> void:
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if is_dedicated_server and sender_id != room_host_peer_id and sender_id != 1:
		push_warning("Non-host peer %d tried to start room match!" % sender_id)
		return
	if not can_start_match():
		return
	start_game(scene_path)

func _sanitize_player_info(info: Dictionary) -> Dictionary:
	# only keep the lobby fields the game understands, since clients send this dictionary
	var raw_name: Variant = info.get("name", "Player")
	var safe_name: String = str(raw_name).strip_edges() if raw_name is String else "Player"
	if safe_name.is_empty():
		safe_name = "Player"
	safe_name = safe_name.left(MAX_PLAYER_NAME_LENGTH)

	var raw_color: Variant = info.get("color", Color.WHITE)
	var safe_color: Color = raw_color if raw_color is Color else Color.WHITE
	safe_color = Color(
		clampf(safe_color.r, 0.0, 1.0),
		clampf(safe_color.g, 0.0, 1.0),
		clampf(safe_color.b, 0.0, 1.0),
		clampf(safe_color.a, 0.0, 1.0)
	)

	var safe_powers: Array[String] = []
	var raw_powers: Variant = info.get("powers", [])
	for _slot_index in range(MAX_EQUIPPED_POWERS):
		safe_powers.append("")
	if raw_powers is Array:
		for slot_index in range(min(raw_powers.size(), MAX_EQUIPPED_POWERS)):
			var power: Variant = raw_powers[slot_index]
			if power is String and VALID_POWERS.has(power) and not safe_powers.has(power):
				safe_powers[slot_index] = power

	return {
		"name": safe_name,
		"color": safe_color,
		"powers": safe_powers,
		"ready": true
	}

@rpc("authority", "reliable")
func _sync_players(updated_players: Dictionary) -> void:
	# so ts is where the client actually receives the latest syncronizated player roster
	players = updated_players
	player_list_changed.emit()

func report_player_death(player_id: int) -> void:
	# the host tells everybody when a ball is out, so spikes n void zones agree too
	if not is_in_room():
		return
	if is_host:
		_queue_player_death(player_id)
	else:
		_request_player_death.rpc_id(1, player_id)

@rpc("any_peer", "reliable")
func _request_player_death(player_id: int) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	# clients can report their own locally detected death, but cant claim a kill
	# for some other player n force the round to end
	if sender_id != player_id or not players.has(sender_id):
		return
	_queue_player_death(player_id)

func _queue_player_death(player_id: int) -> void:
	_pending_player_deaths[player_id] = true
	if _death_batch_scheduled:
		return
	_death_batch_scheduled = true
	call_deferred("_broadcast_pending_player_deaths")

func _broadcast_pending_player_deaths() -> void:
	_death_batch_scheduled = false
	if _pending_player_deaths.is_empty() or not is_host:
		_pending_player_deaths.clear()
		return
	var player_ids := PackedInt32Array()
	for player_id in _pending_player_deaths.keys():
		player_ids.append(int(player_id))
	_pending_player_deaths.clear()
	_sync_player_deaths.rpc(player_ids)

@rpc("authority", "call_local", "reliable")
func _sync_player_deaths(player_ids: PackedInt32Array) -> void:
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and not player.is_queued_for_deletion() and player_ids.has(int(player.get("player_id"))):
			if player.has_method("apply_authoritative_death"):
				player.apply_authoritative_death()

func start_game(scene_path: String = "res://Areas/Grass1.tscn") -> void:
	if not is_host:
		return
	if not can_start_match():
		return
	_begin_match_scene_transition(scene_path)

func change_level(scene_path: String) -> void:
	# transitions everybody connected over to the next level in between rounds
	if not is_host:
		return
	_begin_match_scene_transition(scene_path)

func _begin_match_scene_transition(scene_path: String) -> void:
	if is_scene_transitioning:
		return
	_scene_transition_id += 1
	_scene_ready_peers.clear()
	_scene_transition_finish_sent = false
	_load_match_scene.rpc(scene_path, _scene_transition_id)

@rpc("authority", "call_local", "reliable")
func _load_match_scene(scene_path: String, transition_id: int) -> void:
	# pause per-player RPCs first so packets dont target nodes after a map is freed
	if transition_id < _scene_transition_id:
		return
	_scene_transition_id = transition_id
	is_scene_transitioning = true
	_scene_ready_peers.clear()
	_scene_transition_finish_sent = false
	is_match_active = true
	print("Loading scene: ", scene_path, " (is_host: ", is_host, ", peer_id: ", multiplayer.get_unique_id(), ")")
	match_started.emit()
	await get_tree().create_timer(0.25).timeout
	if transition_id != _scene_transition_id or not is_scene_transitioning:
		return
	var change_error: Error = get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		is_scene_transitioning = false
		_scene_ready_peers.clear()
		push_error("Failed to change match scene to %s: %s" % [scene_path, error_string(change_error)])

func report_match_scene_ready() -> void:
	if not is_scene_transitioning:
		return
	var local_peer_id: int = multiplayer.get_unique_id()
	if is_host:
		_scene_ready_peers[local_peer_id] = true
		_try_finish_match_scene_transition()
	else:
		_report_match_scene_ready_rpc.rpc_id(1, _scene_transition_id, local_peer_id)

@rpc("any_peer", "reliable")
func _report_match_scene_ready_rpc(transition_id: int, peer_id: int) -> void:
	if not is_host or not is_scene_transitioning or transition_id != _scene_transition_id:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != peer_id or not players.has(sender_id):
		return
	_scene_ready_peers[sender_id] = true
	_try_finish_match_scene_transition()

func _try_finish_match_scene_transition() -> void:
	if not is_host or not is_scene_transitioning or _scene_transition_finish_sent:
		return
	for peer_id in players.keys():
		if not _scene_ready_peers.has(int(peer_id)):
			return
	_scene_transition_finish_sent = true
	_resume_match_scene.rpc(_scene_transition_id)

@rpc("authority", "call_local", "reliable")
func _resume_match_scene(transition_id: int) -> void:
	if transition_id != _scene_transition_id:
		return
	is_scene_transitioning = false
	_scene_ready_peers.clear()
	_scene_transition_finish_sent = false

func broadcast_blast(blast_position: Vector2, blast_radius: float, victim_ids: PackedInt32Array, bomb_id: String) -> void:
	# host picks who got caught so every screen agrees on the same deaths
	if not is_host:
		return
	var knockback_ids := PackedInt32Array()
	for player in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(player) or player.is_queued_for_deletion():
			continue
		if "is_dead" in player and player.is_dead:
			continue
		var player_id: int = int(player.get("player_id"))
		if not victim_ids.has(player_id) and player.global_position.distance_to(blast_position) <= blast_radius * BLAST_KNOCKBACK_RADIUS_SCALE:
			knockback_ids.append(player_id)
	_apply_blast.rpc(blast_position, blast_radius, victim_ids, knockback_ids, bomb_id)

@rpc("authority", "call_local", "reliable")
func _apply_blast(blast_position: Vector2, blast_radius: float, victim_ids: PackedInt32Array, knockback_ids: PackedInt32Array, bomb_id: String) -> void:
	# make every peer play the same boom and apply the host's result
	if not bomb_id.is_empty():
		_remember_resolved_bomb(bomb_id)
	_spawn_blast_visual(blast_position, blast_radius)
	if not bomb_id.is_empty():
		for bomb in get_tree().get_nodes_in_group("bomb"):
			if is_instance_valid(bomb) and bomb.get("bomb_id") == bomb_id:
				bomb.queue_free()

	for player in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(player) or player.is_queued_for_deletion():
			continue
		var player_id: int = int(player.get("player_id"))
		if victim_ids.has(player_id):
			if player.has_method("apply_authoritative_death"):
				player.apply_authoritative_death()
		elif knockback_ids.has(player_id) and (bool(player.get("is_local_player")) or bool(player.get("is_tutorial_dummy"))) and player.has_method("apply_blast_knockback"):
			player.apply_blast_knockback(blast_position, blast_radius * BLAST_KNOCKBACK_RADIUS_SCALE, BLAST_KNOCKBACK_FORCE)

func _spawn_blast_visual(blast_position: Vector2, blast_radius: float) -> void:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	var explosion := Node2D.new()
	explosion.set_script(ExplosionScript)
	explosion.radius = blast_radius
	scene_root.add_child(explosion)
	explosion.global_position = blast_position

func has_resolved_bomb(bomb_id: String) -> bool:
	if bomb_id.is_empty():
		return false
	var expires_at: int = int(resolved_bomb_expiries.get(bomb_id, 0))
	if expires_at <= Time.get_ticks_msec():
		resolved_bomb_expiries.erase(bomb_id)
		return false
	return true

func _remember_resolved_bomb(bomb_id: String) -> void:
	var now_msec: int = Time.get_ticks_msec()
	for expired_id in resolved_bomb_expiries.keys():
		if int(resolved_bomb_expiries[expired_id]) <= now_msec:
			resolved_bomb_expiries.erase(expired_id)
	resolved_bomb_expiries[bomb_id] = now_msec + 10000

func request_bomb_detonation(bomb_id: String) -> void:
	# a client may see a collision a frame before the host, so ask the host copy
	# to pop that same bomb instead of leaving this screen's copy frozen forever
	if bomb_id.is_empty() or not is_in_room():
		return
	if is_host:
		_detonate_bomb_by_id(bomb_id)
	else:
		_request_bomb_detonation.rpc_id(1, bomb_id)

@rpc("any_peer", "reliable")
func _request_bomb_detonation(bomb_id: String) -> void:
	if not is_host or bomb_id.is_empty():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1 or not players.has(sender_id):
		return
	_detonate_bomb_by_id(bomb_id)

func _detonate_bomb_by_id(bomb_id: String) -> void:
	for bomb in get_tree().get_nodes_in_group("bomb"):
		if is_instance_valid(bomb) and not bomb.is_queued_for_deletion() and bomb.get("bomb_id") == bomb_id:
			bomb.call("_explode")
			return
