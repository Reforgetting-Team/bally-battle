extends Control

# settings screen so ppl can adjust volume n other lil options n stuff

@onready var back_button: TextureButton = %BackButton
@onready var settings_backdrop: ColorRect = get_node_or_null("SettingsBackdrop")
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var debug_check: CheckButton = %DebugCheckButton

# graphics controls
@onready var fps_option: OptionButton = %FPSOptionButton
@onready var vsync_check: CheckButton = %VSyncCheckButton
@onready var window_mode_box: HBoxContainer = %WindowModeBox
@onready var window_mode_option: OptionButton = %WindowModeOptionButton

# dropdown labels n the real Engine.max_fps values behind em
const FPS_OPTIONS: Array = [
	{"label": "30 FPS", "value": 30},
	{"label": "60 FPS", "value": 60},
	{"label": "90 FPS", "value": 90},
	{"label": "120 FPS", "value": 120},
	{"label": "144 FPS", "value": 144},
	{"label": "240 FPS", "value": 240},
	{"label": "Unlimited", "value": 0},
]

func _ready() -> void:
	UITransitions.animate_in(self, [back_button, settings_backdrop])

	if master_slider:
		master_slider.value = PlayerData.master_volume
		master_slider.value_changed.connect(_on_master_changed)

	if music_slider:
		music_slider.value = PlayerData.music_volume
		music_slider.value_changed.connect(_on_music_changed)

	if debug_check:
		debug_check.button_pressed = PlayerData.debug_mode
		debug_check.toggled.connect(_on_debug_toggled)

	_setup_graphics_controls()

func _setup_graphics_controls() -> void:
	# fps limit dropdown, populate it fresh n select whatever we last saved
	if fps_option:
		fps_option.clear()
		var selected_index := 0
		for i in range(FPS_OPTIONS.size()):
			var opt = FPS_OPTIONS[i]
			fps_option.add_item(opt.label)
			fps_option.set_item_metadata(i, opt.value)
			if opt.value == PlayerData.fps_limit:
				selected_index = i
		fps_option.selected = selected_index
		fps_option.item_selected.connect(_on_fps_selected)

	if vsync_check:
		vsync_check.button_pressed = PlayerData.vsync_enabled
		vsync_check.toggled.connect(_on_vsync_toggled)

	# hide desktop window modes where the platform owns the window
	if OS.has_feature("mobile") or OS.has_feature("web"):
		if window_mode_box:
			window_mode_box.visible = false
		return

	if window_mode_option:
		window_mode_option.clear()
		window_mode_option.add_item("Windowed")
		window_mode_option.add_item("Borderless Window")
		window_mode_option.add_item("Fullscreen")
		window_mode_option.selected = clamp(PlayerData.window_mode, 0, 2)
		window_mode_option.item_selected.connect(_on_window_mode_selected)

func _on_debug_toggled(is_on: bool) -> void:
	PlayerData.debug_mode = is_on
	PlayerData.save_data()

func _on_master_changed(val: float) -> void:
	PlayerData.master_volume = val
	PlayerData.save_data()
	PlayerData.apply_audio_settings()

func _on_music_changed(val: float) -> void:
	PlayerData.music_volume = val
	PlayerData.save_data()
	PlayerData.apply_audio_settings()

func _on_fps_selected(index: int) -> void:
	PlayerData.fps_limit = fps_option.get_item_metadata(index)
	PlayerData.save_data()
	PlayerData.apply_graphics_settings()

func _on_vsync_toggled(is_on: bool) -> void:
	PlayerData.vsync_enabled = is_on
	PlayerData.save_data()
	PlayerData.apply_graphics_settings()

func _on_window_mode_selected(index: int) -> void:
	PlayerData.window_mode = index
	PlayerData.save_data()
	PlayerData.apply_graphics_settings()

func _on_back_pressed() -> void:
	back_button.disabled = true
	var return_action := Callable(self, "_go_to_main_menu")
	var settings_owner := get_parent()
	if settings_owner and settings_owner.has_method("close_settings"):
		return_action = Callable(settings_owner, "close_settings")
	UITransitions.animate_out(self, return_action, [back_button, settings_backdrop])
	UITransitions.animate_node_out_up(back_button, Callable())

func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://Menu/MainMenu.tscn")
