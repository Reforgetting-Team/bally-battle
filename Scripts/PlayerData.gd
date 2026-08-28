extends Node

# saves your customized name and color to disk so you don't lose it on restart

var player_name: String = "Player"
var skin_color: Color = Color(0.2, 0.6, 1.0, 1.0)
var save_path: String = "user://player_data.cfg"
var config: ConfigFile = ConfigFile.new()

func _ready() -> void:
	load_data()

func load_data() -> void:
	# load whatever color/name we picked last time
	var err = config.load(save_path)
	if err == OK:
		if config.has_section_key("player", "skin_color"):
			skin_color = config.get_value("player", "skin_color", skin_color)
		if config.has_section_key("player", "name"):
			player_name = config.get_value("player", "name", player_name)

func save_data() -> void:
	# write our customization to config file
	config.set_value("player", "skin_color", skin_color)
	config.set_value("player", "name", player_name)
	config.save(save_path)
