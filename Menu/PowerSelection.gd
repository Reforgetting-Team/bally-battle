extends Control

# power/ability selection menu, so ts is where u pick ur loadout basically.
# each of the 3 balls is now a FIXED slot tied to a specific mouse button
# (Left/Middle/Right click in-game), n clicking a slot pops open a lil
# picker so u can choose WHICH power goes in that slot, or clear it out
# entirely. no more "1st power u equip = left click" order-based nonsense,
# u pick exactly whats where

const NetworkManagerScript = preload("res://Scripts/NetworkManager.gd")
const PowerBallTexture = preload("res://Menu/PowerBall.png")
const DashTexture = preload("res://Menu/Dash.png")
const SpikyTexture = preload("res://Menu/Spiky.png")
# bomb art isnt guaranteed to be in the project yet (res://Menu/Bomb.png),
# so this one gets loaded at runtime w/ a guard instead of preloaded, else
# this whole menu scene would refuse to open the second that files missing

const SLOT_MOUSE_HINTS: Array = ["Left Click", "Middle Click", "Right Click"]

@onready var back_button: TextureButton = %BackButton
@onready var done_button: Button = %DoneButton
@onready var slot_1_ball: TextureRect = %Slot1Ball
@onready var slot_1_icon: TextureRect = %Slot1Icon
@onready var slot_1_plus: TextureRect = get_node_or_null("%Slot1Ball/PlusIcon")
@onready var slot_2_ball: TextureRect = %Slot2Ball
@onready var slot_2_icon: TextureRect = %Slot2Icon
@onready var slot_2_plus: TextureRect = get_node_or_null("%Slot2Ball/PlusIcon")
@onready var slot_3_ball: TextureRect = %Slot3Ball
@onready var slot_3_icon: TextureRect = %Slot3Icon
@onready var slot_3_plus: TextureRect = get_node_or_null("%Slot3Ball/PlusIcon")
@onready var ability_title_label: Label = %AbilityTitleLabel
@onready var ability_desc_label: Label = %AbilityDescLabel
@onready var count_label: Label = %CountLabel

# repurposed from the old equip/unequip toggle button, now just a quick way
# to empty out whichever slot ur currently looking at w/o opening the picker
@onready var clear_slot_btn: Button = %Slot1Button

@onready var picker_panel: Control = %PowerPickerPanel
@onready var picker_dim: ColorRect = %PickerDim
@onready var picker_dash_btn: TextureButton = %PickerDashOption
@onready var picker_spiky_btn: TextureButton = %PickerSpikyOption
@onready var picker_bomb_btn: TextureButton = %PickerBombOption
@onready var picker_clear_btn: Button = %PickerClearOption

var slot_balls: Array = []
var slot_icons: Array = []
var slot_pluses: Array = []
var focused_slot_index: int = 0 # whichever slot the details panel is currently describing

func _ready() -> void:
	UITransitions.animate_in(self, [back_button])

	# old saves might still have a short/pre-slot-rework array, pad it out to
	# exactly 3 fixed slots so index 0/1/2 always maps to a real mouse button
	while PlayerData.equipped_powers.size() < 3:
		PlayerData.equipped_powers.append("")

	slot_balls = [slot_1_ball, slot_2_ball, slot_3_ball]
	slot_icons = [slot_1_icon, slot_2_icon, slot_3_icon]
	slot_pluses = [slot_1_plus, slot_2_plus, slot_3_plus]

	for ball in slot_balls:
		if ball:
			ball.texture = PowerBallTexture

	# picker option icons, assigned here at runtime same as the slot icons
	# (bomb needs the ResourceLoader guard, dash/spiky are safe to preload)
	if picker_dash_btn:
		picker_dash_btn.texture_normal = DashTexture
		picker_dash_btn.tooltip_text = "Dash"
	if picker_spiky_btn:
		picker_spiky_btn.texture_normal = SpikyTexture
		picker_spiky_btn.tooltip_text = "Spiky"
	if picker_bomb_btn and ResourceLoader.exists("res://Menu/Bomb.png"):
		var bomb_tex := load("res://Menu/Bomb.png") as Texture2D
		if bomb_tex:
			picker_bomb_btn.texture_normal = bomb_tex
			picker_bomb_btn.tooltip_text = "Bomb"

	_refresh_all_slots()

	for i in range(3):
		var ball = slot_balls[i]
		if ball:
			ball.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			ball.gui_input.connect(_on_slot_clicked.bind(i))

	if picker_dash_btn:
		picker_dash_btn.pressed.connect(_on_picker_option_chosen.bind("dash"))
	if picker_spiky_btn:
		picker_spiky_btn.pressed.connect(_on_picker_option_chosen.bind("spiky"))
	if picker_bomb_btn:
		picker_bomb_btn.pressed.connect(_on_picker_option_chosen.bind("bomb"))
	if picker_clear_btn:
		picker_clear_btn.pressed.connect(_on_picker_clear_chosen)
	if picker_dim:
		picker_dim.gui_input.connect(_on_picker_dim_input)
	if clear_slot_btn:
		clear_slot_btn.pressed.connect(_on_clear_focused_slot_pressed)

	_close_picker()

func _icon_texture_for(power_name: String) -> Texture2D:
	match power_name:
		"dash":
			return DashTexture
		"spiky":
			return SpikyTexture
		"bomb":
			if ResourceLoader.exists("res://Menu/Bomb.png"):
				return load("res://Menu/Bomb.png") as Texture2D
	return null

func _refresh_all_slots() -> void:
	for i in range(3):
		_refresh_slot_visual(i)
	_update_count_label()
	_update_details_panel(focused_slot_index)

func _refresh_slot_visual(slot_index: int) -> void:
	var power_name: String = PlayerData.equipped_powers[slot_index]
	var ball = slot_balls[slot_index]
	var icon = slot_icons[slot_index]
	var plus = slot_pluses[slot_index]

	if power_name == "":
		if icon:
			icon.visible = false
		if plus:
			plus.visible = true
		if ball:
			ball.modulate.a = 0.55
	else:
		if icon:
			icon.texture = _icon_texture_for(power_name)
			icon.visible = true
			icon.modulate.a = 1.0
		if plus:
			plus.visible = false
		if ball:
			ball.modulate.a = 1.0

func _update_count_label() -> void:
	if not count_label:
		return
	var filled := 0
	for p in PlayerData.equipped_powers:
		if p != "":
			filled += 1
	count_label.text = "EQUIPPED: %d / 3" % filled

func _update_details_panel(slot_index: int) -> void:
	var power_name: String = PlayerData.equipped_powers[slot_index]
	var mouse_hint: String = SLOT_MOUSE_HINTS[slot_index]

	if clear_slot_btn:
		clear_slot_btn.disabled = (power_name == "")
		clear_slot_btn.text = "CLEAR SLOT" if power_name != "" else "EMPTY"

	if power_name == "":
		if ability_title_label:
			ability_title_label.text = "EMPTY SLOT"
		if ability_desc_label:
			ability_desc_label.text = "Nothing equipped here yet.\nTap this slot to pick a power for %s." % mouse_hint
		return

	if ability_title_label:
		ability_title_label.text = power_name.to_upper()

	match power_name:
		"dash":
			if ability_desc_label:
				ability_desc_label.text = "Burst forward with incredible speed!\nTrigger in-game: %s (or SHIFT / J)\nCooldown: 2 seconds" % mouse_hint
		"spiky":
			if ability_desc_label:
				ability_desc_label.text = "Sprout sharp triangles around your body!\nTouching opponents eliminates them instantly.\nSteering, jumping and dashing are all locked while its active.\nDuration: 3.5s | Trigger: %s (or E / F / K)\nCooldown: 2 seconds" % mouse_hint
		"bomb":
			if ability_desc_label:
				ability_desc_label.text = "Hold to aim a bomb, release to chuck it!\nIts 3.5s fuse starts as soon as u pull it out, so it can pop in ur hand or mid-air.\nTouch another player n it explodes right away.\nMovement, jumping, dashing n spiky are locked while holding it.\nTrigger: %s (or Q)\nCooldown: 2 seconds" % mouse_hint

func _on_slot_clicked(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		focused_slot_index = slot_index
		_update_details_panel(slot_index)
		_open_picker(slot_index)

func _open_picker(slot_index: int) -> void:
	focused_slot_index = slot_index
	if picker_panel:
		picker_panel.visible = true
	_refresh_picker_highlight()

func _close_picker() -> void:
	if picker_panel:
		picker_panel.visible = false

func _refresh_picker_highlight() -> void:
	# dim out whichever option is already sitting in THIS slot so its obvious
	# what youd be picking again vs swapping smth new into it
	var current_power: String = PlayerData.equipped_powers[focused_slot_index]
	if picker_dash_btn:
		picker_dash_btn.modulate.a = 0.5 if current_power == "dash" else 1.0
	if picker_spiky_btn:
		picker_spiky_btn.modulate.a = 0.5 if current_power == "spiky" else 1.0
	if picker_bomb_btn:
		picker_bomb_btn.modulate.a = 0.5 if current_power == "bomb" else 1.0

func _on_picker_option_chosen(power_name: String) -> void:
	_assign_power_to_slot(focused_slot_index, power_name)
	PlayerData.save_data()
	_close_picker()
	_refresh_all_slots()

func _on_picker_clear_chosen() -> void:
	PlayerData.equipped_powers[focused_slot_index] = ""
	PlayerData.save_data()
	_close_picker()
	_refresh_all_slots()

func _on_clear_focused_slot_pressed() -> void:
	PlayerData.equipped_powers[focused_slot_index] = ""
	PlayerData.save_data()
	_refresh_all_slots()

func _assign_power_to_slot(slot_index: int, power_name: String) -> void:
	# if that power's already chilling in a different slot, swap the two
	# instead of just duping it into both, that way every power stays unique
	# n whatever WAS in this slot doesnt just vanish into thin air, it hops
	# over to wherever the new power used to live
	var existing_index := PlayerData.equipped_powers.find(power_name)
	var previous_power: String = PlayerData.equipped_powers[slot_index]

	if existing_index != -1 and existing_index != slot_index:
		PlayerData.equipped_powers[existing_index] = previous_power

	PlayerData.equipped_powers[slot_index] = power_name

func _on_picker_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_picker()

func _on_done_pressed() -> void:
	done_button.disabled = true
	PlayerData.save_data()

	var network_mgr = get_node_or_null("/root/NetworkManager")
	if not network_mgr:
		network_mgr = NetworkManagerScript.instance

	if network_mgr and NetworkManagerScript.peer != null:
		network_mgr.set_player_ready(true)
		network_mgr.update_player_info(PlayerData.player_name, PlayerData.skin_color, PlayerData.equipped_powers)

	UITransitions.animate_out(self, _go_to_next_menu, [back_button])

func _go_to_next_menu() -> void:
	# if were already in a room or lobby, go straight back to it, otherwise show room mode picker
	if NetworkManagerScript.peer != null:
		if not PlayerData.current_room_code.is_empty():
			get_tree().change_scene_to_file("res://Menu/RoomLobby.tscn")
			return
		get_tree().change_scene_to_file("res://Menu/Lobby.tscn")
		return
	get_tree().change_scene_to_file("res://Menu/RoomSelect.tscn")

func _on_back_pressed() -> void:
	back_button.disabled = true
	PlayerData.save_data()
	UITransitions.animate_out(self, _go_to_customization, [back_button])

func _go_to_customization() -> void:
	get_tree().change_scene_to_file("res://Menu/CharacterCustomization.tscn")
