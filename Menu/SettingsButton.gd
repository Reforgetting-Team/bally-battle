extends TextureButton

# settings button on title screen
# ts opens the settings menu so you can tweak stuff

func _ready() -> void:
	UITransitions.animate_node_in(self)

func _on_pressed() -> void:
	disabled = true
	UITransitions.animate_node_out(self, _go_to_settings)

func _go_to_settings() -> void:
	get_tree().change_scene_to_file("res://Menu/Settings.tscn")
