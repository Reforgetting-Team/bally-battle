extends Node

# saves ur customized name n color to disk so u dont lose it on restart lol

var player_name: String = "Player"
var skin_color: Color = Color(0.2, 0.6, 1.0, 1.0)
var equipped_powers: Array = ["dash"]
var debug_mode: bool = false # lets u test multiplayer solo n see all the nerd stats
var save_path: String = "user://player_data.cfg"
var config: ConfigFile = ConfigFile.new()

# --- graphics settings ---
# fps_limit: 0 means unlimited (Engine.max_fps also takes 0 as unlimited)
var fps_limit: int = 0
var vsync_enabled: bool = true
# window_mode: 0 = windowed, 1 = borderless window, 2 = fullscreen. only
# actually matters on desktop, mobile/web are always fullscreen anyway so
# theres no point applying it there (see Settings.gd, it hides the control too)
var window_mode: int = 2

func _ready() -> void:
	load_data()
	apply_graphics_settings()

func load_data() -> void:
	# load whatever color/name/powers we picked last time we played
	var err = config.load(save_path)
	if err == OK:
		if config.has_section_key("player", "skin_color"):
			skin_color = config.get_value("player", "skin_color", skin_color)
		if config.has_section_key("player", "name"):
			player_name = config.get_value("player", "name", player_name)
		if config.has_section_key("player", "equipped_powers"):
			equipped_powers = config.get_value("player", "equipped_powers", ["dash"])
		if config.has_section_key("debug", "debug_mode"):
			debug_mode = config.get_value("debug", "debug_mode", false)
		if config.has_section_key("graphics", "fps_limit"):
			fps_limit = config.get_value("graphics", "fps_limit", fps_limit)
		if config.has_section_key("graphics", "vsync_enabled"):
			vsync_enabled = config.get_value("graphics", "vsync_enabled", vsync_enabled)
		if config.has_section_key("graphics", "window_mode"):
			window_mode = config.get_value("graphics", "window_mode", window_mode)

func save_data() -> void:
	# write our customization out to the config file so its there next time
	config.set_value("player", "skin_color", skin_color)
	config.set_value("player", "name", player_name)
	config.set_value("player", "equipped_powers", equipped_powers)
	config.set_value("debug", "debug_mode", debug_mode)
	config.set_value("graphics", "fps_limit", fps_limit)
	config.set_value("graphics", "vsync_enabled", vsync_enabled)
	config.set_value("graphics", "window_mode", window_mode)
	config.save(save_path)

func apply_graphics_settings() -> void:
	# actually pushes the saved graphics settings into the engine/display
	# server, called once at boot n again whenever settings change live
	Engine.max_fps = fps_limit

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)

	# window mode is a desktop-only concept, mobile/web is always fullscreen
	# n DisplayServer.window_set_mode() is a no-op (or worse, undefined) there
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
