extends Control

# customization menu script - picks character color and updates the shader in real time

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")

@onready var color_picker: ColorPicker = $CenterContainer/HBoxContainer/ColorPicker
@onready var character_sprite: Sprite2D = $CenterContainer/HBoxContainer/Character/CharacterSprite
var mat: ShaderMaterial

func _ready() -> void:
	if character_sprite:
		# make sure our shader material is unique so we dont accidentally color everything
		if character_sprite.material is ShaderMaterial:
			mat = character_sprite.material.duplicate() as ShaderMaterial
			character_sprite.material = mat
		elif character_sprite.material == null:
			var shader = load("res://Character/recolor.gdshader") as Shader
			mat = ShaderMaterial.new()
			mat.shader = shader
			character_sprite.material = mat

	# apply the saved color
	if mat:
		mat.set_shader_parameter("skin_color", PlayerData.skin_color)

	if color_picker:
		color_picker.color = PlayerData.skin_color
		if not color_picker.color_changed.is_connected(_on_color_picker_color_changed):
			color_picker.color_changed.connect(_on_color_picker_color_changed)

func _on_color_picker_color_changed(color: Color) -> void:
	# update preview and save as you drag the color wheel
	if mat:
		mat.set_shader_parameter("skin_color", color)
	PlayerData.skin_color = color
	PlayerData.save_data()

	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	# if were in a lobby while doing this, update our color for everyone in real time
	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.update_player_info(PlayerData.player_name, color)

func _on_done_pressed() -> void:
	# locked in the drip, head over to lobby
	PlayerData.save_data()

	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.set_player_ready(true)
		network_mgr.update_player_info(PlayerData.player_name, PlayerData.skin_color)

	get_tree().change_scene_to_file("res://Menu/Lobby.tscn")

func _on_back_pressed() -> void:
	# bail back to main menu
	PlayerData.save_data()

	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.leave_game()

	get_tree().change_scene_to_file("res://Menu/MainMenu.tscn")
