extends TextureButton

# play button on title screen

func _on_pressed() -> void:
	# lets go customize our ball
	get_tree().change_scene_to_file("res://Menu/CharacterCustomization.tscn")
