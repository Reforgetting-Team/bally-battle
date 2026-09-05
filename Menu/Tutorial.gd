extends TextureButton

# tutorial button on the title screen, for the noobs lol jk jk

func _ready() -> void:
	UITransitions.animate_node_in(self)

func _on_pressed() -> void:
	# gotta disable it so it doesnt get double tapped mid animation
	disabled = true
	UITransitions.animate_node_out(self, _go_to_tutorial)

func _go_to_tutorial() -> void:
	get_tree().change_scene_to_file("res://Areas/Tutorial.tscn")
