extends TextureButton

# so this button actually closes the game instead of just sitting there looking cute

func _ready() -> void:
	UITransitions.animate_node_in(self)

func _on_pressed() -> void:
	disabled = true
	UITransitions.animate_node_out(self, _exit_game)

func _exit_game() -> void:
	get_tree().quit()
