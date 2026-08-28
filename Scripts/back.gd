extends TextureButton

# classic back button script

func _on_back_pressed() -> void:
	# take me back home
	get_tree().change_scene_to_file("res://Menu/MainMenu.tscn")
