extends Node

# saves ur customized name n color to disk so u dont lose it on restart lol

var player_name: String = "Player"
var skin_color: Color = Color(0.2, 0.6, 1.0, 1.0)
var equipped_powers: Array = ["dash", "", ""] # fixed 3 slots now (Left/Middle/Right click), "" = empty slot
var debug_mode: bool = false # lets u test multiplayer solo n see all the nerd stats
var save_path: String = "user://player_data.cfg"
var config: ConfigFile = ConfigFile.new()

# graphics stuff, 0 fps means unlimited
var fps_limit: int = 0
var vsync_enabled: bool = true
# 0 windowed, 1 borderless, 2 fullscreen. phones n web ignore this
var window_mode: int = 2

# audio volume levels (0.0 to 1.0 linear)
var master_volume: float = 1.0
var music_volume: float = 1.0

func _ready() -> void:
	load_data()
	apply_graphics_settings()
	apply_audio_settings()

func load_data() -> void:
	# load whatever color/name/powers we picked last time we played
	var err = config.load(save_path)
	if err == OK:
		if config.has_section_key("player", "skin_color"):
			skin_color = config.get_value("player", "skin_color", skin_color)
		if config.has_section_key("player", "name"):
			player_name = config.get_value("player", "name", player_name)
		if config.has_section_key("player", "equipped_powers"):
			equipped_powers = config.get_value("player", "equipped_powers", ["dash", "", ""])
			# pad old saves so left/middle/right always have a slot
			while equipped_powers.size() < 3:
				equipped_powers.append("")
			if equipped_powers.size() > 3:
				equipped_powers = equipped_powers.slice(0, 3)
		if config.has_section_key("debug", "debug_mode"):
			debug_mode = config.get_value("debug", "debug_mode", false)
		if config.has_section_key("graphics", "fps_limit"):
			fps_limit = config.get_value("graphics", "fps_limit", fps_limit)
		if config.has_section_key("graphics", "vsync_enabled"):
			vsync_enabled = config.get_value("graphics", "vsync_enabled", vsync_enabled)
		if config.has_section_key("graphics", "window_mode"):
			window_mode = config.get_value("graphics", "window_mode", window_mode)
		if config.has_section_key("audio", "master_volume"):
			master_volume = clampf(float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
		if config.has_section_key("audio", "music_volume"):
			music_volume = clampf(float(config.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)

func save_data() -> void:
	# write our customization out to the config file so its there next time
	config.set_value("player", "skin_color", skin_color)
	config.set_value("player", "name", player_name)
	config.set_value("player", "equipped_powers", equipped_powers)
	config.set_value("debug", "debug_mode", debug_mode)
	config.set_value("graphics", "fps_limit", fps_limit)
	config.set_value("graphics", "vsync_enabled", vsync_enabled)
	config.set_value("graphics", "window_mode", window_mode)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.save(save_path)

func apply_audio_settings() -> void:
	# push volume sliders straight into the engine buses
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx != -1:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(master_volume, 0.0001)))
	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(maxf(music_volume, 0.0001)))
	elif is_inside_tree() and has_node("/root/Music"):
		var music_node: Node = get_node("/root/Music")
		if "volume_db" in music_node:
			music_node.volume_db = linear_to_db(maxf(music_volume, 0.0001))

func apply_graphics_settings() -> void:
	# push saved graphics into the game now
	Engine.max_fps = fps_limit

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)

	# phones n web own their window mode, dont fight the platform
	if OS.has_feature("mobile") or OS.has_feature("web"):
		return

	match window_mode:
		0: # windowed
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1: # borderless window
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2: # fullscreen
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
