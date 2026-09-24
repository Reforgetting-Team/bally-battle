@tool
extends McpTestSuite

func test_player_script_loads() -> void:
	assert_true(load("res://Areas/Player.gd") != null, "player script should load")
