extends Control

# Power / Ability Selection Menu
# Allows selecting up to 3 powers (Dash & Spiky!)
# Visually displays the PowerChooser panel with ball containers for each slot

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")
const PowerBallTexture = preload("res://Menu/PowerBall.png")
const DashTexture = preload("res://Menu/Dash.png")
const SpikyTexture = preload("res://Menu/Spiky.png")

@onready var back_button: TextureButton = %BackButton
@onready var done_button: Button = %DoneButton
@onready var slot_1_ball: TextureRect = %Slot1Ball
@onready var slot_1_icon: TextureRect = %Slot1Icon
@onready var slot_2_ball: TextureRect = %Slot2Ball
@onready var slot_2_icon: TextureRect = %Slot2Icon
@onready var slot_2_plus: TextureRect = get_node_or_null("%Slot2Ball/PlusIcon")
@onready var slot_3_ball: TextureRect = %Slot3Ball
@onready var ability_title_label: Label = %AbilityTitleLabel
@onready var ability_desc_label: Label = %AbilityDescLabel
@onready var equip_btn: Button = %Slot1Button
@onready var count_label: Label = %CountLabel

var selected_power: String = "dash" # currently inspected power ("dash" or "spiky")

func _ready() -> void:
	UITransitions.animate_in(self, [back_button])

	_setup_slot_balls()
	_update_equipped_ui()

	if equip_btn:
		equip_btn.pressed.connect(_on_equip_toggled)

	if slot_1_ball:
		slot_1_ball.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot_1_ball.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				selected_power = "dash"
				_update_equipped_ui()
		)

	if slot_2_ball:
		slot_2_ball.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot_2_ball.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				selected_power = "spiky"
				_update_equipped_ui()
		)

func _setup_slot_balls() -> void:
	if slot_1_ball:
		slot_1_ball.texture = PowerBallTexture
	if slot_1_icon:
		slot_1_icon.texture = DashTexture

	if slot_2_ball:
		slot_2_ball.texture = PowerBallTexture
	if slot_2_icon:
		slot_2_icon.texture = SpikyTexture

	if slot_3_ball:
		slot_3_ball.texture = PowerBallTexture

func _update_equipped_ui() -> void:
	var is_dash_equipped: bool = PlayerData.equipped_powers.has("dash")
	var is_spiky_equipped: bool = PlayerData.equipped_powers.has("spiky")

	# Slot 1 (Dash) visuals
	if is_dash_equipped:
		slot_1_ball.modulate.a = 1.0
		slot_1_icon.modulate.a = 1.0
	else:
		slot_1_ball.modulate.a = 0.55
		slot_1_icon.modulate.a = 0.4

	# Slot 2 (Spiky) visuals
	if is_spiky_equipped:
		slot_2_ball.modulate.a = 1.0
		if slot_2_icon:
			slot_2_icon.visible = true
			slot_2_icon.modulate.a = 1.0
		if slot_2_plus:
			slot_2_plus.visible = false
	else:
		if slot_2_icon:
			slot_2_icon.visible = true
			slot_2_icon.modulate.a = 0.35
		if slot_2_plus:
			slot_2_plus.visible = false
		slot_2_ball.modulate.a = 0.55

	if count_label:
		count_label.text = "EQUIPPED: %d / 3" % PlayerData.equipped_powers.size()

	# Details panel for the selected power
	var is_selected_equipped: bool = PlayerData.equipped_powers.has(selected_power)
	if equip_btn:
		equip_btn.text = "EQUIPPED" if is_selected_equipped else "EQUIP"

	if selected_power == "dash":
		if ability_title_label:
			ability_title_label.text = "DASH"
		if ability_desc_label:
			ability_desc_label.text = "Burst forward with incredible speed!\nTrigger in-game: SHIFT / RIGHT CLICK\nCooldown: 1.2 seconds"
	elif selected_power == "spiky":
		if ability_title_label:
			ability_title_label.text = "SPIKY"
		if ability_desc_label:
			ability_desc_label.text = "Sprout sharp triangles around your body!\nTouching opponents eliminates them instantly.\nSteering is locked, but momentum continues rolling.\nDuration: 3.5s | Trigger: E / F / K"

func _on_equip_toggled() -> void:
	if PlayerData.equipped_powers.has(selected_power):
		PlayerData.equipped_powers.erase(selected_power)
	else:
		if PlayerData.equipped_powers.size() < 3:
			PlayerData.equipped_powers.append(selected_power)
	PlayerData.save_data()
	_update_equipped_ui()

func _on_done_pressed() -> void:
	done_button.disabled = true
	PlayerData.save_data()

	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.set_player_ready(true)
		network_mgr.update_player_info(PlayerData.player_name, PlayerData.skin_color, PlayerData.equipped_powers)

	UITransitions.animate_out(self, _go_to_lobby, [back_button])

func _go_to_lobby() -> void:
	get_tree().change_scene_to_file("res://Menu/Lobby.tscn")

func _on_back_pressed() -> void:
	back_button.disabled = true
	PlayerData.save_data()
	UITransitions.animate_out(self, _go_to_customization, [back_button])

func _go_to_customization() -> void:
	get_tree().change_scene_to_file("res://Menu/CharacterCustomization.tscn")
