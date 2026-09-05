extends CanvasLayer
class_name MobileControlsPanel

# mobile touch controls for the ball physics, so ts is basically a virtual joystick + action buttons

@onready var joystick_base: Control = $JoystickBase
@onready var joystick_knob: Control = $JoystickBase/Knob
@onready var jump_button: TouchScreenButton = $JumpButton
@onready var dash_button: TouchScreenButton = $DashButton
@onready var spiky_button: TouchScreenButton = $SpikyButton

# cache these once instead of get_node_or_null-ing by string every frame,
# way cheaper n we grab both Visual and Visual/Icon while were at it
@onready var jump_visual: CanvasItem = jump_button.get_node_or_null("Visual")
@onready var dash_visual: CanvasItem = dash_button.get_node_or_null("Visual")
@onready var spiky_visual: CanvasItem = spiky_button.get_node_or_null("Visual")
@onready var dash_icon: CanvasItem = dash_button.get_node_or_null("Visual/Icon")
@onready var spiky_icon: CanvasItem = spiky_button.get_node_or_null("Visual/Icon")


var joystick_touch_index: int = -1
var joystick_radius: float = 60.0
var joystick_center: Vector2 = Vector2.ZERO
var joystick_vector: Vector2 = Vector2.ZERO

# keeps track of which touch is actually driving the joystick rn
var active_touches: Dictionary = {}

# button press tracking so we can tell when its a fresh "just pressed" n not just held
var jump_pressed_last_frame: bool = false
var dash_pressed_last_frame: bool = false
var spiky_pressed_last_frame: bool = false

var jump_just_pressed: bool = false
var dash_just_pressed: bool = false
var spiky_just_pressed: bool = false

var is_mobile_active: bool = false

func _ready() -> void:
	# only show up on mobile/touch devices OR when were just testing it
	# (set debug_always_show in project settings for that)
	var always_show = ProjectSettings.get_setting("display/mobile/always_show_controls", false)
	if not always_show and not OS.has_feature("mobile") and not OS.has_feature("web_android") and not OS.has_feature("web_ios"):
		visible = false
		is_mobile_active = false
		return
	
	is_mobile_active = true
	
	# position the buttons based on screen size (theyre all centered shapes now)
	_position_controls()
	
	# get the joystick values set up n ready to go
	joystick_center = joystick_base.global_position + joystick_base.size / 2
	joystick_radius = joystick_base.size.x / 2.0

	# sensible default before any Player node checks in w our real equipped
	# powers or smth (matches whatever we last picked in power selection)
	set_equipped_powers(PlayerData.equipped_powers)

	# were an autoload so we persist across every scene, main menu included
	# lol. gotta hide ourselves right away if we didnt boot straight into a match
	_update_gameplay_visibility()
	
	# gotta make sure touch input is actually turned on
	set_process_input(true)


func _position_controls() -> void:
	var screen_size = get_viewport().get_visible_rect().size
	
	# since shape_centered is true, the position IS the center of the button
	# beefed up the margins so we dont clip into the rounded corners n stuff
	
	# jump button, bottom right (100px margin from bottom, 80px from right)
	jump_button.position = Vector2(screen_size.x - 80, screen_size.y - 100)
	
	# dash button, sits right above jump (100px spacing vertically)
	dash_button.position = Vector2(screen_size.x - 80, screen_size.y - 200)
	
	# spiky button, off to the left n diagonally between dash n jump
	spiky_button.position = Vector2(screen_size.x - 180, screen_size.y - 150)
	
	# joystick, bottom left (same y as jump button since the anchor's centered)
	joystick_base.position = Vector2(100, screen_size.y - 200)

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
	
	# update all the button press states
	_update_button_states()

func _update_gameplay_visibility() -> void:
	# only actual gameplay scenes (Grass1-4, Tutorial, etc, see MatchManager)
	# are tagged w this group or smth, so menus n lobby screens just never match
	var scene := get_tree().current_scene
	visible = scene != null and scene.is_in_group("gameplay_scene")


func _update_button_states() -> void:
	# gotta figure out "just pressed" for each button
	var jump_now = jump_button and jump_button.is_pressed()
	var dash_now = dash_button and dash_button.is_pressed()
	var spiky_now = spiky_button and spiky_button.is_pressed()
	
	jump_just_pressed = jump_now and not jump_pressed_last_frame
	dash_just_pressed = dash_now and not dash_pressed_last_frame
	spiky_just_pressed = spiky_now and not spiky_pressed_last_frame
	
	jump_pressed_last_frame = jump_now
	dash_pressed_last_frame = dash_now
	spiky_pressed_last_frame = spiky_now
	
	# lil visual feedback so buttons pop more when actually pressed
	_update_button_visual_feedback()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# check if this touch landed on the joystick area
		var touch_pos = event.position
		var dist_to_joystick = touch_pos.distance_to(joystick_center)
		
		if dist_to_joystick < joystick_radius * 2.5:  # generous hit area so it feels forgiving
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
	return jump_just_pressed

func is_dash_pressed() -> bool:
	return dash_button != null and dash_button.is_pressed()

func is_dash_just_pressed() -> bool:
	return dash_just_pressed

func is_spiky_pressed() -> bool:
	return spiky_button != null and spiky_button.is_pressed()

func is_spiky_just_pressed() -> bool:
	return spiky_just_pressed

func is_active() -> bool:
	return is_mobile_active and visible

func _update_button_visual_feedback() -> void:
	# make the buttons pop more opaque when actually held down, lil juice
	# (using the cached Visual refs from _ready instead of get_node_or_null
	# every single frame, thats what was chewing up cycles before)
	if jump_visual:
		jump_visual.modulate.a = 1.0 if jump_pressed_last_frame else 0.7
	
	if dash_visual:
		dash_visual.modulate.a = 1.0 if dash_pressed_last_frame else 0.7
	
	if spiky_visual:
		spiky_visual.modulate.a = 1.0 if spiky_pressed_last_frame else 0.7

func set_button_colors(player_color: Color) -> void:
	# so ts tints the button icons to match whatever color the player picked
	if dash_icon:
		dash_icon.modulate = player_color
	
	if spiky_icon:
		spiky_icon.modulate = player_color

func set_equipped_powers(powers: Array) -> void:
	# only show the buttons for powers we actually got equipped or smth, no
	# point showing a Spiky button on mobile if u didnt even bring spiky lol
	if dash_button:
		dash_button.visible = powers.has("dash")
	
	if spiky_button:
		spiky_button.visible = powers.has("spiky")
