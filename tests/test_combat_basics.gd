@tool
extends McpTestSuite

const PlayerScript = preload("res://Areas/Player.gd")
const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")

func test_grenade_fuse_and_startup_match_bopl_timing() -> void:
	assert_true(is_equal_approx(PlayerScript.BOMB_FUSE_TIME, 3.5), "grenade fuse should keep ticking for 3.5 seconds")
	assert_eq(PlayerScript.BOMB_STARTUP_FRAMES, 14, "grenade should keep its short 14 frame windup")
	assert_true(is_equal_approx(PlayerScript.BOMB_COOLDOWN, 2.0), "grenade cooldown should be 2 seconds")

func test_blast_knockback_pushes_the_player_away() -> void:
	var player = PlayerScript.new()
	player.global_position = Vector2(100.0, 0.0)
	player.velocity = Vector2.ZERO
	player.apply_blast_knockback(Vector2.ZERO, 200.0, 400.0)
	assert_true(player.velocity.x > 0.0, "blast should push a player away from its center")
	assert_true(player.velocity.y < 0.0, "a close blast should lift the player too")
	assert_true(is_equal_approx(player.velocity.length(), 200.0), "push strength should fade with distance from the blast")
	player.free()

func test_client_lobby_data_is_sanitized() -> void:
	var network_manager = NetworkManagerScript.new()
	var info: Dictionary = network_manager._sanitize_player_info({
		"name": "   " + "a".repeat(24) + "   ",
		"color": Color(2.0, -1.0, 0.5, 3.0),
		"powers": ["dash", "unknown", "bomb", "bomb", 42],
		"ready": false
	})
	assert_eq(info["name"].length(), NetworkManagerScript.MAX_PLAYER_NAME_LENGTH, "long names should get clipped")
	assert_eq(info["color"], Color(1.0, 0.0, 0.5, 1.0), "colors should stay inside the normal range")
	assert_eq(info["powers"], ["dash", "", "bomb"], "invalid powers should leave their slot empty so click mappings stay put")
	assert_true(info["ready"], "new players should enter with the normal ready state")
	network_manager.free()
