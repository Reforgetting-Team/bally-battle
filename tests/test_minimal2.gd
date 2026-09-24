@tool
extends McpTestSuite

func test_match_maps_are_present() -> void:
	for map_path in ["res://Areas/Grass1.tscn", "res://Areas/Grass2.tscn", "res://Areas/Grass3.tscn", "res://Areas/Grass4.tscn"]:
		assert_true(ResourceLoader.exists(map_path), "%s should exist" % map_path)
