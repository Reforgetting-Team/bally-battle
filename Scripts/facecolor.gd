extends Control

# customization menu script, so ts is where u pick ur character color n it
# updates the shader live so u see it change in real time, kinda satisfying

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")

@onready var color_picker: ColorPicker = $CenterContainer/HBoxContainer/ColorPicker
@onready var character_sprite: Sprite2D = $CenterContainer/HBoxContainer/Character/CharacterSprite
@onready var back_button: TextureButton = $Back
@onready var done_button: Button = $DoneButton
var mat: ShaderMaterial

func _ready() -> void:
	# CenterContainer holds both the ColorPicker n the Character so animating
	# it moves both of em together. Back button stays put on entrance tho
	UITransitions.animate_in(self, [back_button])

	if character_sprite:
		# gotta make sure our shader material is unique so we dont accidentally recolor everything else too
		if character_sprite.material is ShaderMaterial:
			mat = character_sprite.material.duplicate() as ShaderMaterial
			character_sprite.material = mat
		elif character_sprite.material == null:
			var shader = load("res://Character/recolor.gdshader") as Shader
			mat = ShaderMaterial.new()
			mat.shader = shader
			character_sprite.material = mat

	# slap on whatever color they had saved last time
	if mat:
		mat.set_shader_parameter("skin_color", PlayerData.skin_color)

	if color_picker:
		color_picker.color = PlayerData.skin_color
		if not color_picker.color_changed.is_connected(_on_color_picker_color_changed):
			color_picker.color_changed.connect(_on_color_picker_color_changed)

func _on_color_picker_color_changed(color: Color) -> void:
	# update the preview n save it as u drag the color wheel around
	if mat:
		mat.set_shader_parameter("skin_color", color)
	PlayerData.skin_color = color
	PlayerData.save_data()

	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	# if were in a lobby while doin this, sync our color to everyone else live
	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.update_player_info(PlayerData.player_name, color)

func _on_done_pressed() -> void:
	# locked in the drip, head over to power selection
	done_button.disabled = true
	PlayerData.save_data()

	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.update_player_info(PlayerData.player_name, PlayerData.skin_color, PlayerData.equipped_powers)

	UITransitions.animate_out(self, _go_to_power_selection, [back_button])

func _go_to_power_selection() -> void:
	get_tree().change_scene_to_file("res://Menu/PowerSelection.tscn")

func _on_back_pressed() -> void:
	# bail back to main menu
	back_button.disabled = true
	PlayerData.save_data()

	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.leave_game()

	UITransitions.animate_out(self, _go_to_main_menu)

func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://Menu/MainMenu.tscn")
