extends CanvasLayer

# ts is the advanced debug overlay that shows all the nerd stats when debug mode is on
# toggles with F3 or via Settings

var overlay_panel: PanelContainer
var info_label: Label

func _ready() -> void:
	layer = 120 # above all gameplay and UI
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()

func _create_ui() -> void:
	overlay_panel = PanelContainer.new()
	overlay_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_panel.position = Vector2(850, 10)
	overlay_panel.custom_minimum_size = Vector2(290, 180)
	overlay_panel.modulate = Color(1, 1, 1, 0.9)
	overlay_panel.visible = PlayerData.debug_mode

	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	overlay_panel.add_child(margin)

	info_label = Label.new()
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", 3)
	margin.add_child(info_label)

	add_child(overlay_panel)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			PlayerData.debug_mode = not PlayerData.debug_mode
			PlayerData.save_data()
			if overlay_panel:
				overlay_panel.visible = PlayerData.debug_mode
			get_viewport().set_input_as_handled()
		elif PlayerData.debug_mode:
			if event.keycode == KEY_F1:
				# suicide test key to test death & victory
				var players = get_tree().get_nodes_in_group("player")
				for p in players:
					if "is_local_player" in p and p.is_local_player and p.has_method("die"):
						p.die()
						break
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_F2:
				# quick skip to next match level
				var match_mgr = get_tree().current_scene
				if match_mgr and match_mgr.has_method("advance_to_next_level"):
					match_mgr.advance_to_next_level()
					get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not PlayerData.debug_mode:
		if overlay_panel and overlay_panel.visible:
			overlay_panel.visible = false
		return

	if overlay_panel and not overlay_panel.visible:
		overlay_panel.visible = true

	if not info_label:
		return

	var fps := Engine.get_frames_per_second()
	var mem := OS.get_static_memory_usage() / (1024.0 * 1024.0)
	var scene_name := ""
	if get_tree().current_scene:
		scene_name = get_tree().current_scene.scene_file_path.get_file()

	# find local player stats
	var pos_str := "N/A"
	var vel_str := "N/A"
	var state_str := "Normal"
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if "is_local_player" in p and p.is_local_player:
			pos_str = "(%d, %d)" % [int(p.global_position.x), int(p.global_position.y)]
			vel_str = "(%d, %d)" % [int(p.velocity.x), int(p.velocity.y)]
			if "is_dead" in p and p.is_dead:
				state_str = "DEAD"
			elif "is_spiky" in p and p.is_spiky:
				state_str = "SPIKY (%.1fs)" % p.spiky_time_remaining
			elif "is_dashing" in p and p.is_dashing:
				state_str = "DASHING"
			break

	# network stats
	var net_status := "Solo"
	var peer_count := 0
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null:
		var is_host = multiplayer.is_server()
		net_status = "Host" if is_host else "Client"
		peer_count = multiplayer.get_peers().size() + 1

	var text := "=== DEBUG MODE ===\n"
	text += "FPS: %d | RAM: %.1f MB\n" % [fps, mem]
	text += "Scene: %s\n" % scene_name
	text += "Net: %s (Peers: %d)\n" % [net_status, peer_count]
	text += "Player Pos: %s\n" % pos_str
	text += "Player Vel: %s\n" % vel_str
	text += "State: %s\n" % state_str
	text += "------------------\n"
	text += "F1: Suicide Test\n"
	text += "F2: Skip Level\n"
	text += "F3: Toggle Debug"

	info_label.text = text
