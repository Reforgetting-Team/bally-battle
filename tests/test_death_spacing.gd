extends McpTestSuite

# throwaway verification test for the death-corner spacing logic - not part
# of the permanent suite, just used to sanity-check die() before shipping

const PlayerScript = preload("res://Areas/Player.gd")

func test_two_simultaneous_deaths_step_left_and_down() -> void:
	PlayerScript.reset_deaths()

	var player_scene: PackedScene = preload("res://Character/Player.tscn")
	var p1 = player_scene.instantiate()
	var p2 = player_scene.instantiate()

	p1.die()
	p2.die()

	assert(p1.position.x > p2.position.x, "second death should be to the LEFT of the first")
	assert(p2.position.y > p1.position.y, "second death should be slightly LOWER than the first")
	assert(is_equal_approx(p1.position.x - p2.position.x, 170.0), "x step should be DEATH_STEP_X (170)")
	assert(is_equal_approx(p2.position.y - p1.position.y, 45.0), "y step should be DEATH_STEP_Y (45)")
	assert(p1.is_dead and p2.is_dead, "both should be marked dead")

	p1.free()
	p2.free()
