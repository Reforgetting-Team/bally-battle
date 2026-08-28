extends Control

# lobby screen controller - deals with buttons and room UI and player lists

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")
const RecolorShader = preload("res://Character/recolor.gdshader")
const CharacterTexture = preload("res://Character/Character.png")

@onready var name_input: LineEdit = %NameInput
@onready var ip_input: LineEdit = %IPInput
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton
@onready var back_button: TextureButton = %BackButton
@onready var status_label: Label = %StatusLabel
@onready var connection_panel: VBoxContainer = %ConnectionPanel
@onready var host_ip_input: LineEdit = %HostIPInput
@onready var host_port_input: LineEdit = %HostPortInput
@onready var room_panel: VBoxContainer = %RoomPanel
@onready var player_list_container: VBoxContainer = %PlayerListContainer

var network_mgr: Node = null

func _ready() -> void:
	network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	name_input.text = PlayerData.player_name
	ip_input.text = "127.0.0.1"
	host_port_input.text = str(NetworkManagerScript.DEFAULT_PORT)

	if network_mgr:
		if not network_mgr.player_list_changed.is_connected(_on_player_list_changed):
			network_mgr.player_list_changed.connect(_on_player_list_changed)
		if not network_mgr.connection_succeeded.is_connected(_on_connection_succeeded):
			network_mgr.connection_succeeded.connect(_on_connection_succeeded)
		if not network_mgr.connection_failed.is_connected(_on_connection_failed):
			network_mgr.connection_failed.connect(_on_connection_failed)
		if not network_mgr.server_disconnected.is_connected(_on_server_disconnected):
			network_mgr.server_disconnected.connect(_on_server_disconnected)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	if not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)
	name_input.text_changed.connect(_on_name_changed)

	# came back from customization while in a room? cool, tell everyone we are back
	if NetworkManagerScript.peer != null:
		if network_mgr:
			network_mgr.set_player_ready(true)
			network_mgr.update_player_info(PlayerData.player_name, PlayerData.skin_color)
		_update_ui_state(true)
		_on_player_list_changed()
	else:
		_update_ui_state(false)

func _on_name_changed(new_name: String) -> void:
	var clean_name = new_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Player"
	PlayerData.player_name = clean_name
	PlayerData.save_data()

	# sync the new tag to everyone if we are already chilling in a room
	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.update_player_info(clean_name, PlayerData.skin_color)

func _update_ui_state(in_room: bool) -> void:
	# swap between the join/host buttons and the actual lobby room
	connection_panel.visible = not in_room
	room_panel.visible = in_room
	start_button.visible = in_room and NetworkManagerScript.is_host
	if in_room:
		if NetworkManagerScript.is_host:
			var bound_to = host_ip_input.text.strip_edges()
			var bind_desc = bound_to if not bound_to.is_empty() else "all interfaces"
			status_label.text = "Hosting on %s, port %s. Share your ZeroTier / LAN IP!" % [bind_desc, host_port_input.text]
		else:
			status_label.text = "In room. Waiting for host to start..."

func _on_host_pressed() -> void:
	PlayerData.player_name = name_input.text.strip_edges()
	if PlayerData.player_name.is_empty():
		PlayerData.player_name = "Player 1"
	PlayerData.save_data()

	if not network_mgr:
		network_mgr = get_node_or_null("/root/NetworkManager")
		if not network_mgr:
			network_mgr = NetworkManagerScript.instance

	if network_mgr:
		var bind_ip = host_ip_input.text.strip_edges()
		var port = int(host_port_input.text) if host_port_input.text.is_valid_int() else NetworkManagerScript.DEFAULT_PORT

		# catch the bad-address case before we even try, with a helpful message,
		# instead of a bare "error 20"
		if not bind_ip.is_empty() and not NetworkManagerScript.get_bindable_addresses().has(bind_ip):
			status_label.text = "Can't bind to %s. This PC's addresses: %s" % [bind_ip, ", ".join(NetworkManagerScript.get_bindable_addresses())]
			return

		var err = network_mgr.create_game(bind_ip, port)
		if err == OK:
			_update_ui_state(true)
			_on_player_list_changed()
		else:
			status_label.text = "Failed to host match: error %d" % err

func _on_join_pressed() -> void:
	PlayerData.player_name = name_input.text.strip_edges()
	if PlayerData.player_name.is_empty():
		PlayerData.player_name = "Player 2"
	PlayerData.save_data()

	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"

	status_label.text = "Connecting to %s..." % ip
	join_button.disabled = true

	if not network_mgr:
		network_mgr = get_node_or_null("/root/NetworkManager")
		if not network_mgr:
			network_mgr = NetworkManagerScript.instance

	if network_mgr:
		var err = network_mgr.join_game(ip)
		if err != OK:
			status_label.text = "Failed to connect: error %d" % err
			join_button.disabled = false

func _on_connection_succeeded() -> void:
	join_button.disabled = false
	_update_ui_state(true)
	_on_player_list_changed()

func _on_connection_failed() -> void:
	join_button.disabled = false
	_update_ui_state(false)
	status_label.text = "Connection failed. Please check IP address and ensure host is running."

func _on_server_disconnected() -> void:
	join_button.disabled = false
	_update_ui_state(false)
	status_label.text = "Host disconnected."

func _on_player_list_changed() -> void:
	# rebuild the player list UI whenever someone joins leaves or changes color
	for child in player_list_container.get_children():
		child.queue_free()

	var any_customizing: bool = false
	var customizing_names: Array = []

	for peer_id in NetworkManagerScript.players.keys():
		var p_info = NetworkManagerScript.players[peer_id]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		hbox.alignment = BoxContainer.ALIGNMENT_BEGIN

		# show their cute ball sprite with their customized color shader applied
		var char_icon = TextureRect.new()
		char_icon.custom_minimum_size = Vector2(36, 36)
		char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		char_icon.texture = CharacterTexture

		var mat = ShaderMaterial.new()
		mat.shader = RecolorShader
		mat.set_shader_parameter("skin_color", p_info.get("color", Color.WHITE))
		char_icon.material = mat

		hbox.add_child(char_icon)

		# player name and badges like host / you / customizing
		var name_lbl = Label.new()
		var p_name = p_info.get("name", "Player")
		var is_ready = p_info.get("ready", true)
		var is_local = (peer_id == multiplayer.get_unique_id()) or (NetworkManagerScript.is_host and peer_id == 1)
		var is_host_peer = (peer_id == 1)
		
		var tags = []
		if is_host_peer:
			tags.append("Host")
		if is_local:
			tags.append("You")
		if not is_ready:
			tags.append("Customizing...")
			any_customizing = true
			customizing_names.append(p_name)

		if tags.size() > 0:
			name_lbl.text = "%s (%s)" % [p_name, ", ".join(tags)]
		else:
			name_lbl.text = p_name

		name_lbl.add_theme_font_size_override("font_size", 20)
		hbox.add_child(name_lbl)

		player_list_container.add_child(hbox)

	# dont let the host start if someone is still in customization
	if NetworkManagerScript.is_host:
		if any_customizing:
			start_button.disabled = true
			status_label.text = "Waiting for %s to finish customizing..." % ", ".join(customizing_names)
		else:
			start_button.disabled = false
			status_label.text = "All players ready! Click Start Match when ready."

func _on_start_pressed() -> void:
	if NetworkManagerScript.is_host and network_mgr:
		if NetworkManagerScript.can_start_match():
			status_label.text = "Starting match..."
			network_mgr.start_game("res://Areas/Tutorial.tscn")
		else:
			status_label.text = "Cannot start match while players are customizing."

func _on_leave_pressed() -> void:
	# rage quit the room
	if network_mgr:
		network_mgr.leave_game()
	_update_ui_state(false)
	status_label.text = "Left lobby."

func _on_back_pressed() -> void:
	# go back to customize without leaving room and tell host to wait up
	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.set_player_ready(false)
	get_tree().change_scene_to_file("res://Menu/CharacterCustomization.tscn")
