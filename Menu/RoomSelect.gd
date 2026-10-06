extends Control

# room selection menu, so ts lets u choose whether u wanna spin up a fresh room,
# hop into ur friend's code room on the global server, or do custom ip stuff

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")

@onready var back_button: TextureButton = %BackButton
@onready var create_room_btn: TextureButton = %CreateRoomButton
@onready var join_room_btn: TextureButton = %JoinRoomButton
@onready var custom_ip_btn: TextureButton = %CustomIPButton
@onready var status_label: Label = %StatusLabel

# join dialog modal elements
@onready var join_modal: Control = %JoinModal
@onready var code_input: LineEdit = %CodeInput
@onready var modal_join_btn: Button = %ModalJoinButton
@onready var modal_cancel_btn: Button = %ModalCancelButton
@onready var modal_paste_btn: Button = %ModalPasteButton
@onready var modal_error_label: Label = %ModalErrorLabel

var http_req: HTTPRequest
var is_requesting: bool = false
var pending_action: String = "" # "create" or "join"

func _ready() -> void:
	UITransitions.animate_in(self, [back_button, join_modal])

	# setup http request node for talking to our vps coordinator
	http_req = HTTPRequest.new()
	http_req.timeout = 7.0
	add_child(http_req)
	http_req.request_completed.connect(_on_http_request_completed)

	# background check to see if global tunnel URL was updated on GitHub
	var url_discovery_req := HTTPRequest.new()
	url_discovery_req.timeout = 3.0
	add_child(url_discovery_req)
	url_discovery_req.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if response_code == 200:
			var remote_url: String = body.get_string_from_utf8().strip_edges()
			if (remote_url.begins_with("https://") or remote_url.begins_with("http://")) and ("trycloudflare.com" in PlayerData.dedicated_server_address or PlayerData.dedicated_server_address == PlayerData.DEFAULT_GLOBAL_SERVER):
				PlayerData.dedicated_server_address = remote_url
		url_discovery_req.queue_free()
	)
	url_discovery_req.request("https://raw.githubusercontent.com/Reforgetting-Team/bally-battle/server/server_url.txt")

	create_room_btn.pressed.connect(_on_create_room_pressed)
	join_room_btn.pressed.connect(_on_join_room_pressed)
	custom_ip_btn.pressed.connect(_on_custom_ip_pressed)
	back_button.pressed.connect(_on_back_pressed)

	modal_join_btn.pressed.connect(_on_modal_join_confirm_pressed)
	modal_cancel_btn.pressed.connect(_on_modal_cancel_pressed)
	modal_paste_btn.pressed.connect(_on_modal_paste_pressed)
	code_input.text_submitted.connect(func(_text): _on_modal_join_confirm_pressed())
	code_input.text_changed.connect(_on_code_input_changed)

	join_modal.visible = false
	status_label.text = ""

	_setup_button_hover_effects(create_room_btn)
	_setup_button_hover_effects(join_room_btn)
	_setup_button_hover_effects(custom_ip_btn)

func _setup_button_hover_effects(btn: TextureButton) -> void:
	# cute lil bounce/scale effect when hovering over the cards
	btn.pivot_offset = btn.size * 0.5
	btn.mouse_entered.connect(func():
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	btn.mouse_exited.connect(func():
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)

func _get_server_base_url() -> String:
	# builds the base url to talk to our global server coordinator
	var addr: String = PlayerData.dedicated_server_address.strip_edges()
	if addr.is_empty() or addr == "10.24.60.105":
		addr = PlayerData.DEFAULT_GLOBAL_SERVER
	var port: int = PlayerData.dedicated_server_port if PlayerData.dedicated_server_port > 0 else 8910

	# if player typed a full domain or tunnel url (like https://something.trycloudflare.com)
	if addr.begins_with("http://") or addr.begins_with("https://"):
		return addr
	if addr.begins_with("ws://") or addr.begins_with("wss://"):
		return addr.replace("ws://", "http://").replace("wss://", "https://")

	# standard ip / host
	return "http://%s:%d" % [addr, port]

func _get_server_ws_url(room_code: String) -> String:
	# builds websocket url for connecting to the specific room
	var addr: String = PlayerData.dedicated_server_address.strip_edges()
	if addr.is_empty() or addr == "10.24.60.105":
		addr = PlayerData.DEFAULT_GLOBAL_SERVER
	var port: int = PlayerData.dedicated_server_port if PlayerData.dedicated_server_port > 0 else 8910

	if addr.begins_with("https://"):
		return "%s/room/%s" % [addr.replace("https://", "wss://"), room_code]
	if addr.begins_with("http://"):
		return "%s/room/%s" % [addr.replace("http://", "ws://"), room_code]
	if addr.begins_with("wss://") or addr.begins_with("ws://"):
		return "%s/room/%s" % [addr, room_code]

	# plain host or ip
	return "ws://%s:%d/room/%s" % [addr, port, room_code]

func _on_create_room_pressed() -> void:
	if is_requesting:
		return
	is_requesting = true
	pending_action = "create"
	status_label.text = "Creating room on global server..."
	_set_buttons_disabled(true)

	var url = "%s/api/create_room" % _get_server_base_url()
	print("Requesting room creation: ", url)
	var err = http_req.request(url, ["User-Agent: BallyBattle"], HTTPClient.METHOD_POST, "")
	if err != OK:
		is_requesting = false
		_set_buttons_disabled(false)
		status_label.text = "Failed to send request to server (error %d)" % err

func _on_join_room_pressed() -> void:
	if is_requesting:
		return
	# pop open the enter code dialog
	modal_error_label.text = ""
	code_input.text = ""
	join_modal.visible = true
	code_input.grab_focus()

func _on_code_input_changed(new_text: String) -> void:
	var uppercase_code = new_text.to_upper().strip_edges()
	if code_input.text != uppercase_code:
		code_input.text = uppercase_code
		code_input.caret_column = uppercase_code.length()

func _on_modal_paste_pressed() -> void:
	var clip := DisplayServer.clipboard_get().strip_edges().to_upper()
	if not clip.is_empty():
		code_input.text = clip
		code_input.caret_column = clip.length()

func _on_modal_cancel_pressed() -> void:
	join_modal.visible = false
	status_label.text = ""

func _on_modal_join_confirm_pressed() -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.is_empty():
		modal_error_label.text = "Please enter a room code!"
		return
	if is_requesting:
		return

	is_requesting = true
	pending_action = "join"
	modal_error_label.text = "Checking room code..."
	modal_join_btn.disabled = true

	var url = "%s/api/join_room?code=%s" % [_get_server_base_url(), code.uri_encode()]
	print("Checking room: ", url)
	var err = http_req.request(url, ["User-Agent: BallyBattle"], HTTPClient.METHOD_GET, "")
	if err != OK:
		is_requesting = false
		modal_join_btn.disabled = false
		modal_error_label.text = "Failed to connect to server (error %d)" % err

func _on_http_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_requesting = false
	_set_buttons_disabled(false)
	modal_join_btn.disabled = false

	if response_code == 0:
		var err_msg = "Could not reach global server at %s. Check connection or use Custom IP." % PlayerData.dedicated_server_address
		status_label.text = err_msg
		if join_modal.visible:
			modal_error_label.text = err_msg
		return

	var json_str = body.get_string_from_utf8()
	var json = JSON.parse_string(json_str)
	if not (json is Dictionary):
		status_label.text = "Unexpected response from server (code %d)" % response_code
		if join_modal.visible:
			modal_error_label.text = "Server returned invalid response."
		return

	if response_code != 200 or json.get("status", "") != "ok":
		var msg: String = str(json.get("message", "Room not found or expired."))
		status_label.text = msg
		if join_modal.visible:
			modal_error_label.text = msg
		return

	# room found or created successfully!
	var room_code: String = str(json.get("code", "")).to_upper()
	if room_code.is_empty():
		status_label.text = "Server gave an empty room code."
		return

	PlayerData.current_room_code = room_code
	PlayerData.is_room_host = (pending_action == "create")

	status_label.text = "Connecting to room %s..." % room_code
	_connect_and_enter_room(room_code)

func _connect_and_enter_room(room_code: String) -> void:
	var ws_url := _get_server_ws_url(room_code)
	print("Connecting to room WebSocket: ", ws_url)
	var network_mgr: Node = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if not network_mgr:
		status_label.text = "Network manager singleton missing!"
		return

	var err = network_mgr.join_game(ws_url)
	if err != OK:
		status_label.text = "Failed to connect to room (error %d)" % err
		return

	join_modal.visible = false
	UITransitions.animate_out(self, func():
		get_tree().change_scene_to_file("res://Menu/RoomLobby.tscn")
	, [back_button])

func _set_buttons_disabled(val: bool) -> void:
	create_room_btn.disabled = val
	join_room_btn.disabled = val
	custom_ip_btn.disabled = val

func _on_custom_ip_pressed() -> void:
	# bro wanted the old classic multiplayer screen, lets take him there
	create_room_btn.disabled = true
	join_room_btn.disabled = true
	custom_ip_btn.disabled = true
	UITransitions.animate_out(self, func():
		get_tree().change_scene_to_file("res://Menu/Lobby.tscn")
	, [back_button])

func _on_back_pressed() -> void:
	back_button.disabled = true
	UITransitions.animate_out(self, func():
		get_tree().change_scene_to_file("res://Menu/PowerSelection.tscn")
	, [back_button])
