extends TextureButton

# play button on title screen

func _ready() -> void:
	UITransitions.animate_node_in(self)

func _on_pressed() -> void:
	# don't let it get double-tapped mid-animation
	disabled = true
	UITransitions.animate_node_out(self, _go_to_customization)

func _go_to_customization() -> void:
	# lets go customize our ball
	get_tree().change_scene_to_file("res://Menu/CharacterCustomization.tscn")
