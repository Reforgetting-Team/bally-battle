extends TextureButton

# play button on the title screen, this is where the fun starts

func _ready() -> void:
	UITransitions.animate_node_in(self)

func _on_pressed() -> void:
	# gotta disable it so it doesnt get double tapped mid animation lol
	disabled = true
	UITransitions.animate_node_out(self, _go_to_customization)

func _go_to_customization() -> void:
	# lets goo, off to customize our ball
	get_tree().change_scene_to_file("res://Menu/CharacterCustomization.tscn")
