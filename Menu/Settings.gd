extends Control

# settings screen so the player can adjust volume and stuff

@onready var back_button: TextureButton = %BackButton
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var debug_check: CheckButton = %DebugCheckButton

func _ready() -> void:
	UITransitions.animate_in(self, [back_button])

	if master_slider:
		var master_idx := AudioServer.get_bus_index("Master")
		if master_idx != -1:
			master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(master_idx))
		master_slider.value_changed.connect(_on_master_changed)

	if music_slider:
		var music_idx := AudioServer.get_bus_index("Music")
		if music_idx != -1:
			music_slider.value = db_to_linear(AudioServer.get_bus_volume_db(music_idx))
		else:
			music_slider.value = 1.0
		music_slider.value_changed.connect(_on_music_changed)

	if debug_check:
		debug_check.button_pressed = PlayerData.debug_mode
		debug_check.toggled.connect(_on_debug_toggled)

func _on_debug_toggled(is_on: bool) -> void:
	PlayerData.debug_mode = is_on
	PlayerData.save_data()

func _on_master_changed(val: float) -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx != -1:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(max(val, 0.0001)))

func _on_music_changed(val: float) -> void:
	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(max(val, 0.0001)))
	elif has_node("/root/Music"):
		var music_node: Node = get_node("/root/Music")
		if "volume_db" in music_node:
			music_node.volume_db = linear_to_db(max(val, 0.0001))

func _on_back_pressed() -> void:
	back_button.disabled = true
	UITransitions.animate_out(self, _go_to_main_menu, [back_button])
	UITransitions.animate_node_out_up(back_button, Callable())

func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://Menu/MainMenu.tscn")
