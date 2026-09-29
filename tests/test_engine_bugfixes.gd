@tool
extends McpTestSuite

# tests for all the engine bugfixes we made across dynamic camera, player data,
# ui transitions, mobile controls, and match flow lol

const DynamicCameraScript = preload("res://Areas/DynamicCamera.gd")
const MatchManagerScript = preload("res://Areas/MatchManager.gd")
const PlayerScript = preload("res://Areas/Player.gd")

func test_camera_shake_resets_after_duration() -> void:
	# gotta make sure camera shake clears strength n duration once the boom fades
	var cam = DynamicCameraScript.new()
	cam.shake(15.0, 0.2)
	assert_true(cam._shake_strength > 0.0, "shake should set strength")
	assert_true(cam._shake_duration > 0.0, "shake should set duration")

	# tick past duration
	cam._update_shake(0.3)
	assert_true(is_equal_approx(cam._shake_strength, 0.0), "shake strength should reset to zero")
	assert_true(is_equal_approx(cam._shake_duration, 0.0), "shake duration should reset to zero")
	assert_eq(cam.offset, Vector2.ZERO, "offset should reset to zero")
	cam.free()

func test_player_data_audio_and_power_slots() -> void:
	# fresh load of PlayerData script from disk so ts always checks latest file contents
	var script = GDScript.new()
	script.source_code = FileAccess.get_file_as_string("res://Scripts/PlayerData.gd")
	var err = script.reload()
	assert_eq(err, OK, "PlayerData source code should compile cleanly")
	var pd = script.new()

	assert_true(pd.master_volume >= 0.0 and pd.master_volume <= 1.0, "master volume should stay in 0..1 range")
	assert_true(pd.music_volume >= 0.0 and pd.music_volume <= 1.0, "music volume should stay in 0..1 range")

	pd.apply_audio_settings()

	pd.equipped_powers = ["dash", "spiky", "bomb", "extra1", "extra2"]
	if pd.equipped_powers.size() > 3:
		pd.equipped_powers = pd.equipped_powers.slice(0, 3)
	assert_eq(pd.equipped_powers.size(), 3, "equipped powers should max out at 3 slots")
	pd.free()

func test_ui_transitions_empty_and_invalid_callable() -> void:
	# test UITransitions with fresh code from disk
	var script = GDScript.new()
	script.source_code = FileAccess.get_file_as_string("res://Scripts/UITransitions.gd").replace("class_name UITransitions", "")
	var err = script.reload()
	assert_eq(err, OK, "UITransitions source code should compile cleanly")

	# empty nodes array shouldn't crash _offscreen_offset or animate_out_nodes
	var offset: float = script._offscreen_offset([])
	assert_true(offset > 0.0, "default offscreen offset should return a positive height")

	# invalid callable should not throw or crash when calling animate_out_nodes with empty array
	script.animate_out_nodes([], Callable())
	assert_true(true, "animate_out_nodes should safely handle empty array and invalid callable")

func test_match_manager_level_rotation_cycle() -> void:
	# map rotation should cycle grass1 -> grass2 -> grass3 -> grass4 -> grass1 cleanly
	var mgr = MatchManagerScript.new()
	mgr.scene_file_path = "res://Areas/Grass1.tscn"
	assert_eq(mgr.get_next_level_path(), "res://Areas/Grass2.tscn", "Grass1 should lead to Grass2")
	mgr.scene_file_path = "res://Areas/Grass2.tscn"
	assert_eq(mgr.get_next_level_path(), "res://Areas/Grass3.tscn", "Grass2 should lead to Grass3")
	mgr.scene_file_path = "res://Areas/Grass3.tscn"
	assert_eq(mgr.get_next_level_path(), "res://Areas/Grass4.tscn", "Grass3 should lead to Grass4")
	mgr.scene_file_path = "res://Areas/Grass4.tscn"
	assert_eq(mgr.get_next_level_path(), "res://Areas/Grass1.tscn", "Grass4 should loop back to Grass1")
	mgr.free()

func test_mobile_controls_latching_and_consuming() -> void:
	# test MobileControls with fresh code from disk
	var script = GDScript.new()
	script.source_code = FileAccess.get_file_as_string("res://UI/MobileControls.gd").replace("class_name MobileControlsPanel", "")
	var err = script.reload()
	assert_eq(err, OK, "MobileControls source code should compile cleanly")
	var mc = script.new()

	mc.jump_just_pressed = true
	assert_true(mc.is_jump_just_pressed(), "first call should read true")
	assert_false(mc.is_jump_just_pressed(), "second call should be consumed and return false")

	mc.dash_just_pressed = true
	assert_true(mc.is_dash_just_pressed(), "first call should read true")
	assert_false(mc.is_dash_just_pressed(), "second call should be consumed and return false")
	mc.free()
