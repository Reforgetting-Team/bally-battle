extends CanvasLayer
class_name MobileControlsPanel

# mobile touch controls for the ball physics, so ts is basically a virtual joystick + action buttons

const BUTTON_TEXTURE: Texture2D = preload("res://UI/Buttons.png")
const BUTTON_HOVER_TEXTURE: Texture2D = preload("res://UI/ButtonsHover.png")

@onready var joystick_base: Control = $JoystickBase
@onready var joystick_knob: Control = $JoystickBase/Knob
@onready var jump_button: TouchScreenButton = $JumpButton
@onready var dash_button: TouchScreenButton = $DashButton
@onready var spiky_button: TouchScreenButton = $SpikyButton
# bomb button is optional, this scene may not have one added yet, everything
# below is get_node_or_null-guarded so nothing breaks if its missing
@onready var bomb_button: TouchScreenButton = get_node_or_null("BombButton")

# cache these once instead of get_node_or_null-ing by string every frame,
# way cheaper n we grab both Visual and Visual/Icon while were at it
@onready var jump_visual: TextureRect = jump_button.get_node_or_null("Visual") as TextureRect
@onready var dash_visual: TextureRect = dash_button.get_node_or_null("Visual") as TextureRect
@onready var spiky_visual: TextureRect = spiky_button.get_node_or_null("Visual") as TextureRect
@onready var dash_icon: CanvasItem = dash_button.get_node_or_null("Visual/Icon")
@onready var spiky_icon: CanvasItem = spiky_button.get_node_or_null("Visual/Icon")
@onready var bomb_visual: TextureRect = get_node_or_null("BombButton/Visual") as TextureRect
@onready var bomb_icon: CanvasItem = get_node_or_null("BombButton/Visual/Icon")


var joystick_touch_index: int = -1
var joystick_radius: float = 60.0
var joystick_center: Vector2 = Vector2.ZERO
var joystick_vector: Vector2 = Vector2.ZERO

# keeps track of which touch is actually driving the joystick rn
var active_touches: Dictionary = {}

# keep hardware mouse clicks separate from touch-emulated mouse input, so a
# connected mouse works without phone taps accidentally firing power slot 1
var _physical_mouse_seen: bool = false
var _physical_mouse_slots_pressed: Array[bool] = [false, false, false]
var _physical_mouse_slots_just_pressed: Array[bool] = [false, false, false]
var _physical_mouse_slots_just_released: Array[bool] = [false, false, false]

# button press tracking so we can tell when its a fresh "just pressed" n not just held
var jump_pressed_last_frame: bool = false
var dash_pressed_last_frame: bool = false
var spiky_pressed_last_frame: bool = false
var bomb_pressed_last_frame: bool = false

var jump_just_pressed: bool = false
var dash_just_pressed: bool = false
var spiky_just_pressed: bool = false
var bomb_just_pressed: bool = false
var bomb_just_released: bool = false

var is_mobile_active: bool = false
var _layout_reference_size: Vector2 = Vector2(1152.0, 648.0)
var _touch_layout_buttons: Array[TouchScreenButton] = []
var _authored_touch_positions: Array[Vector2] = []

func _ready() -> void:
	# only show up on mobile/touch devices OR when were just testing it
	# (set debug_always_show in project settings for that)
	var always_show = ProjectSettings.get_setting("display/mobile/always_show_controls", false)
	if not always_show and not OS.has_feature("mobile") and not OS.has_feature("web_android") and not OS.has_feature("web_ios"):
		visible = false
		is_mobile_active = false
		return
	
	is_mobile_active = true
	if always_show:
		# make touch buttons visible on desktop when forced on in settings
		for btn in [jump_button, dash_button, spiky_button, bomb_button]:
			if btn:
				btn.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	
	# keep the scene positions as the layout starting point, then stick each
	# touch button to the nearest screen edges when the phone aspect ratio shifts
	_capture_touch_button_layout()
	get_viewport().size_changed.connect(_layout_touch_buttons)
	_layout_touch_buttons()
	
	# get the joystick values set up n ready to go
	joystick_center = joystick_base.global_position + joystick_base.size / 2
	joystick_radius = maxf((joystick_base.size.x - joystick_knob.size.x) / 2.0, 1.0)

	# sensible default before any Player node checks in w our real equipped
	# powers or smth (matches whatever we last picked in power selection)
	set_equipped_powers(PlayerData.equipped_powers)

	# were an autoload so we persist across every scene, main menu included
	# lol. gotta hide ourselves right away if we didnt boot straight into a match
	_update_gameplay_visibility()
	
	# gotta make sure touch input is actually turned on
	set_process_input(true)

func _capture_touch_button_layout() -> void:
	_layout_reference_size = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1152)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 648))
	)
	_touch_layout_buttons = [jump_button, dash_button, spiky_button]
	if bomb_button:
		_touch_layout_buttons.append(bomb_button)

	_authored_touch_positions.clear()
	for button in _touch_layout_buttons:
		_authored_touch_positions.append(button.position)

func _layout_touch_buttons() -> void:
	var screen_size := get_viewport().get_visible_rect().size
	for index in range(_touch_layout_buttons.size()):
		var button: TouchScreenButton = _touch_layout_buttons[index]
		var authored_position: Vector2 = _authored_touch_positions[index]
		var responsive_position := authored_position

		# positions on the right/bottom half keep the scene-authored edge gap
		if authored_position.x > _layout_reference_size.x * 0.5:
			responsive_position.x = screen_size.x - (_layout_reference_size.x - authored_position.x)
		if authored_position.y > _layout_reference_size.y * 0.5:
			responsive_position.y = screen_size.y - (_layout_reference_size.y - authored_position.y)

		button.position = responsive_position

func _process(_delta: float) -> void:
	if not is_mobile_active:
		return

	# keep re-checking every frame whether were actually in a match rn or not,
	# so the buttons pop away the instant we head back to a menu n pop back
	# in the instant a match starts, no need to hunt down every menu transition lol
	_update_gameplay_visibility()

	if not visible:
		return
	
	# joystick position mighta changed so gotta recompute the center every frame
	joystick_center = joystick_base.global_position + joystick_base.size / 2
	joystick_radius = maxf((joystick_base.size.x - joystick_knob.size.x) / 2.0, 1.0)
	
	# update all the button press states
	_update_button_states()

func _update_gameplay_visibility() -> void:
	# only actual gameplay scenes (Grass1-4, Tutorial, etc, see MatchManager)
	# are tagged w this group or smth, so menus n lobby screens just never match
	var scene := get_tree().current_scene
	var should_show_controls: bool = scene != null and scene.is_in_group("gameplay_scene")
	if visible and not should_show_controls:
		_reset_physical_mouse_state()
	visible = should_show_controls

func _reset_physical_mouse_state() -> void:
	_physical_mouse_seen = false
	for slot_index in range(3):
		_physical_mouse_slots_pressed[slot_index] = false
		_physical_mouse_slots_just_pressed[slot_index] = false
		_physical_mouse_slots_just_released[slot_index] = false


func _update_button_states() -> void:
	# gotta figure out "just pressed" for each button
	var jump_now = jump_button and jump_button.is_pressed()
	var dash_now = dash_button and dash_button.is_pressed()
	var spiky_now = spiky_button and spiky_button.is_pressed()
	var bomb_now = bomb_button and bomb_button.is_pressed()
	
	# latch the button down edge so fast taps dont get swallowed by high fps
	if jump_now and not jump_pressed_last_frame:
		jump_just_pressed = true
	if dash_now and not dash_pressed_last_frame:
		dash_just_pressed = true
	if spiky_now and not spiky_pressed_last_frame:
		spiky_just_pressed = true
	if bomb_now and not bomb_pressed_last_frame:
		bomb_just_pressed = true
	if not bomb_now and bomb_pressed_last_frame:
		bomb_just_released = true
	
	jump_pressed_last_frame = jump_now
	dash_pressed_last_frame = dash_now
	spiky_pressed_last_frame = spiky_now
	bomb_pressed_last_frame = bomb_now
	
	# lil visual feedback so buttons pop more when actually pressed
	_update_button_visual_feedback()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_physical_mouse_seen = true
	elif event is InputEventMouseButton:
		_handle_physical_mouse_button(event)

func _handle_physical_mouse_button(event: InputEventMouseButton) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	_physical_mouse_seen = true
	var slot_index: int = _get_power_slot_for_mouse_button(event.button_index)
	if slot_index < 0:
		return
	if event.pressed:
		if not _physical_mouse_slots_pressed[slot_index]:
			_physical_mouse_slots_just_pressed[slot_index] = true
		_physical_mouse_slots_pressed[slot_index] = true
	elif _physical_mouse_slots_pressed[slot_index]:
		_physical_mouse_slots_just_released[slot_index] = true
		_physical_mouse_slots_pressed[slot_index] = false

func _get_power_slot_for_mouse_button(button_index: int) -> int:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return 0
		MOUSE_BUTTON_MIDDLE:
			return 1
		MOUSE_BUTTON_RIGHT:
			return 2
	return -1

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# check if this touch landed on the joystick area
		var touch_pos = event.position
		var dist_to_joystick = touch_pos.distance_to(joystick_center)
		
		if dist_to_joystick < joystick_base.size.x * 1.25:  # keep the big comfy touch area around the round base
			joystick_touch_index = event.index
			active_touches[event.index] = "joystick"
			_update_joystick(touch_pos)
	else:
		# finger lifted off
		if active_touches.has(event.index):
			if active_touches[event.index] == "joystick":
				joystick_touch_index = -1
				joystick_vector = Vector2.ZERO
				joystick_knob.position = joystick_base.size / 2 - joystick_knob.size / 2
			active_touches.erase(event.index)

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == joystick_touch_index:
		_update_joystick(event.position)

func _update_joystick(touch_pos: Vector2) -> void:
	var joystick_offset = touch_pos - joystick_center
	var distance = joystick_offset.length()
	
	# clamp it to the joystick radius so it doesnt go flying off
	if distance > joystick_radius:
		joystick_offset = joystick_offset.normalized() * joystick_radius
		distance = joystick_radius
	
	# move the knob visual so it actually looks like its being dragged
	var knob_offset = joystick_base.size / 2 - joystick_knob.size / 2
	joystick_knob.position = knob_offset + joystick_offset
	
	# normalize it down to a -1..1 vector for the actual movement input
	joystick_vector = joystick_offset / joystick_radius

func get_joystick_vector() -> Vector2:
	return joystick_vector

func is_jump_pressed() -> bool:
	return jump_button != null and jump_button.is_pressed()

func is_jump_just_pressed() -> bool:
	var pressed := jump_just_pressed
	jump_just_pressed = false
	return pressed

func is_dash_pressed() -> bool:
	return dash_button != null and dash_button.is_pressed()

func is_dash_just_pressed() -> bool:
	var pressed := dash_just_pressed
	dash_just_pressed = false
	return pressed

func is_spiky_pressed() -> bool:
	return spiky_button != null and spiky_button.is_pressed()

func is_spiky_just_pressed() -> bool:
	var pressed := spiky_just_pressed
	spiky_just_pressed = false
	return pressed

func is_bomb_pressed() -> bool:
	return bomb_button != null and bomb_button.is_pressed()

func is_bomb_just_pressed() -> bool:
	var pressed := bomb_just_pressed
	bomb_just_pressed = false
	return pressed

func is_bomb_just_released() -> bool:
	var released := bomb_just_released
	bomb_just_released = false
	return released

func is_active() -> bool:
	return is_mobile_active and visible

func has_physical_mouse_input() -> bool:
	return _physical_mouse_seen

func consume_mouse_slot_just_pressed(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _physical_mouse_slots_just_pressed.size():
		return false
	var was_just_pressed: bool = _physical_mouse_slots_just_pressed[slot_index]
	_physical_mouse_slots_just_pressed[slot_index] = false
	return was_just_pressed

func consume_mouse_slot_just_released(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _physical_mouse_slots_just_released.size():
		return false
	var was_just_released: bool = _physical_mouse_slots_just_released[slot_index]
	_physical_mouse_slots_just_released[slot_index] = false
	return was_just_released

func _update_button_visual_feedback() -> void:
	# use the game button art, n swap to its hover look while a button is held
	if jump_visual:
		_set_button_visual(jump_visual, jump_pressed_last_frame)
	
	if dash_visual:
		_set_button_visual(dash_visual, dash_pressed_last_frame)
	
	if spiky_visual:
		_set_button_visual(spiky_visual, spiky_pressed_last_frame)

	if bomb_visual:
		_set_button_visual(bomb_visual, bomb_pressed_last_frame)

func _set_button_visual(button_visual: TextureRect, is_pressed: bool) -> void:
	button_visual.texture = BUTTON_HOVER_TEXTURE if is_pressed else BUTTON_TEXTURE

func set_button_colors(player_color: Color) -> void:
	# so ts tints the button icons to match whatever color the player picked
	if dash_icon:
		dash_icon.modulate = player_color
	
	if spiky_icon:
		spiky_icon.modulate = player_color

	if bomb_icon:
		bomb_icon.modulate = player_color

func set_equipped_powers(powers: Array) -> void:
	# only show the buttons for powers we actually got equipped or smth, no
	# point showing a Spiky button on mobile if u didnt even bring spiky lol
	if dash_button:
		dash_button.visible = powers.has("dash")
	
	if spiky_button:
		spiky_button.visible = powers.has("spiky")

	if bomb_button:
		bomb_button.visible = powers.has("bomb")
