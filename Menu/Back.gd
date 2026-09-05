extends TextureButton


# fires when this node first shows up in the scene tree
func _ready() -> void:
	pass # nothing to set up here rn tbh


func _on_texture_button_pressed() -> void:
	# so ts just yeets u back to the main menu when u click the back button
	get_tree().change_scene_to_file("res://Menu/MainMenu.tscn")
