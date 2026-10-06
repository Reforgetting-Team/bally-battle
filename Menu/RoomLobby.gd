extends Control

# room lobby controller, where you chill with your friends before the brawl begins
# shows your room code so you can copy/paste it to discord/etc and the player roster

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")
const RecolorShader = preload("res://Character/recolor.gdshader")
const CharacterTexture = preload("res://Character/Character.png")

@onready var back_button: TextureButton = %BackButton
@onready var room_code_label: Label = %RoomCodeLabel
@onready var copy_code_btn: Button = %CopyCodeButton
@onready var status_label: Label = %StatusLabel
@onready var player_list_container: VBoxContainer = %PlayerListContainer
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton

var network_mgr: Node = null
var copy_feedback_timer: float = 0.0

func _ready() -> void:
	UITransitions.animate_in(self, [back_button])

	network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	_update_room_code_display()

	if network_mgr:
		if not network_mgr.player_list_changed.is_connected(_on_player_list_changed):
			network_mgr.player_list_changed.connect(_on_player_list_changed)
		if not network_mgr.room_info_updated.is_connected(_on_room_info_updated):
			network_mgr.room_info_updated.connect(_on_room_info_updated)
		if not network_mgr.server_disconnected.is_connected(_on_server_disconnected):
			network_mgr.server_disconnected.connect(_on_server_disconnected)

	copy_code_btn.pressed.connect(_on_copy_code_pressed)
	start_button.pressed.connect(_on_start_match_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	back_button.pressed.connect(_on_back_pressed)

	_on_player_list_changed()

func _process(delta: float) -> void:
	if copy_feedback_timer > 0.0:
		copy_feedback_timer -= delta
		if copy_feedback_timer <= 0.0:
			copy_code_btn.text = "COPY CODE"

func _update_room_code_display() -> void:
	var code = PlayerData.current_room_code
	if code.is_empty():
		code = NetworkManagerScript.current_room_code
	room_code_label.text = "ROOM CODE: %s" % (code if not code.is_empty() else "----")

func _on_room_info_updated(_code: String, _host_id: int) -> void:
	_update_room_code_display()
	_on_player_list_changed()

func _on_copy_code_pressed() -> void:
	var code = PlayerData.current_room_code
	if code.is_empty():
		code = NetworkManagerScript.current_room_code
	if not code.is_empty():
		DisplayServer.clipboard_set(code)
		copy_code_btn.text = "COPIED! ✓"
		copy_feedback_timer = 1.6

func _on_player_list_changed() -> void:
	# rebuild roster whenever someone joins or changes their style
	for child in player_list_container.get_children():
		child.queue_free()

	var local_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var host_id = NetworkManagerScript.room_host_peer_id

	for peer_id in NetworkManagerScript.players.keys():
		var p_info = NetworkManagerScript.players[peer_id]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		hbox.alignment = BoxContainer.ALIGNMENT_BEGIN

		# character icon w/ recolor shader
		var char_icon = TextureRect.new()
		char_icon.custom_minimum_size = Vector2(40, 40)
		char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		char_icon.texture = CharacterTexture

		var mat = ShaderMaterial.new()
		mat.shader = RecolorShader
		mat.set_shader_parameter("skin_color", p_info.get("color", Color.WHITE))
		char_icon.material = mat
		hbox.add_child(char_icon)

		# player name and tags
		var name_lbl = Label.new()
		var p_name = str(p_info.get("name", "Player"))
		var is_local = (peer_id == local_id)
		var is_room_host = (peer_id == host_id)

		var tags: Array = []
		if is_room_host:
			tags.append("Room Host")
		if is_local:
			tags.append("You")

		if tags.size() > 0:
			name_lbl.text = "%s  (%s)" % [p_name, ", ".join(tags)]
		else:
			name_lbl.text = p_name

		name_lbl.add_theme_font_size_override("font_size", 22)
		hbox.add_child(name_lbl)

		player_list_container.add_child(hbox)

	_update_lobby_status_and_buttons()

func _update_lobby_status_and_buttons() -> void:
	var is_room_host = PlayerData.is_room_host or (NetworkManagerScript.room_host_peer_id == multiplayer.get_unique_id())
	var player_count = NetworkManagerScript.players.size()

	start_button.visible = is_room_host

	if is_room_host:
		if not PlayerData.debug_mode and player_count < 2:
			start_button.disabled = true
			status_label.text = "Share the room code with your friends! At least 2 players needed to start."
		else:
			start_button.disabled = false
			if PlayerData.debug_mode and player_count < 2:
				status_label.text = "[DEBUG MODE] 1-player match allowed! Click START MATCH."
			else:
				status_label.text = "All players assembled! Click START MATCH when ready."
	else:
		status_label.text = "In room lobby. Waiting for room host to start the match..."

func _on_start_match_pressed() -> void:
	if not NetworkManagerScript.can_room_host_start():
		status_label.text = "Cannot start match yet!"
		return

	status_label.text = "Starting match on global server..."
	start_button.disabled = true

	if network_mgr and network_mgr.has_method("request_start_room_match"):
		network_mgr.call("request_start_room_match", "res://Areas/Grass1.tscn")
	elif network_mgr:
		network_mgr.start_game("res://Areas/Grass1.tscn")

func _on_server_disconnected() -> void:
	status_label.text = "Disconnected from room server."
	UITransitions.animate_out(self, func():
		get_tree().change_scene_to_file("res://Menu/RoomSelect.tscn")
	, [back_button])

func _on_leave_pressed() -> void:
	if network_mgr:
		network_mgr.leave_game()
	UITransitions.animate_out(self, func():
		get_tree().change_scene_to_file("res://Menu/RoomSelect.tscn")
	, [back_button])

func _on_back_pressed() -> void:
	back_button.disabled = true
	if network_mgr:
		network_mgr.leave_game()
	UITransitions.animate_out(self, func():
		get_tree().change_scene_to_file("res://Menu/RoomSelect.tscn")
	, [back_button])
