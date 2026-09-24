extends CanvasLayer

# so this is like a pause menu but the match keeps moving underneath it lol

const PANEL_TEXTURE: Texture2D = preload("res://Menu/PauseMenu.png")
const CONTINUE_TEXTURE: Texture2D = preload("res://Menu/Continue.png")
const CONTINUE_HOVER_TEXTURE: Texture2D = preload("res://Menu/ContinueHover.png")
const SETTINGS_TEXTURE: Texture2D = preload("res://Menu/Settings.png")
const SETTINGS_HOVER_TEXTURE: Texture2D = preload("res://Menu/SettingsHover.png")
const EXIT_TEXTURE: Texture2D = preload("res://Menu/Exit.png")
const EXIT_HOVER_TEXTURE: Texture2D = preload("res://Menu/ExitHover.png")
const ESCAPE_TEXTURE: Texture2D = preload("res://Menu/Escape.png")
const SETTINGS_SCENE: PackedScene = preload("res://Menu/Settings.tscn")

var pause_content: Control
var panel: TextureRect
var title: Label
var continue_button: TextureButton
var settings_button: TextureButton
var exit_button: TextureButton
var touch_pause_button: TextureButton
var settings_screen: Control
var menu_is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("match_menu_overlay")
	_build_menu()
	get_viewport().size_changed.connect(_layout_menu)
	_layout_menu()
	close_menu()

func _build_menu() -> void:
	pause_content = Control.new()
	pause_content.name = "PauseContent"
	pause_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pause_content)

	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.48)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_content.add_child(dimmer)

	panel = TextureRect.new()
	panel.name = "Panel"
	panel.texture = PANEL_TEXTURE
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_content.add_child(panel)

	title = Label.new()
	title.name = "Title"
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	pause_content.add_child(title)

	continue_button = _make_button("ContinueButton", CONTINUE_TEXTURE, CONTINUE_HOVER_TEXTURE)
	continue_button.pressed.connect(_on_continue_pressed)
	pause_content.add_child(continue_button)

	settings_button = _make_button("SettingsButton", SETTINGS_TEXTURE, SETTINGS_HOVER_TEXTURE)
	settings_button.pressed.connect(_on_settings_pressed)
	pause_content.add_child(settings_button)

	exit_button = _make_button("ExitButton", EXIT_TEXTURE, EXIT_HOVER_TEXTURE)
	exit_button.pressed.connect(_on_exit_pressed)
	pause_content.add_child(exit_button)

	touch_pause_button = TextureButton.new()
	touch_pause_button.name = "TouchPauseButton"
	touch_pause_button.texture_normal = ESCAPE_TEXTURE
	touch_pause_button.texture_hover = ESCAPE_TEXTURE
	touch_pause_button.texture_pressed = ESCAPE_TEXTURE
	touch_pause_button.ignore_texture_size = true
	touch_pause_button.stretch_mode = TextureButton.STRETCH_SCALE
	touch_pause_button.modulate.a = 0.5
	touch_pause_button.tooltip_text = "Open pause menu"
	touch_pause_button.custom_minimum_size = Vector2(60, 60)
	touch_pause_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	touch_pause_button.pressed.connect(func(): set_menu_open(true))
	add_child(touch_pause_button)
	touch_pause_button.visible = _is_mobile_controls_active()

func _make_button(button_name: String, normal_texture: Texture2D, hover_texture: Texture2D) -> TextureButton:
	var button := TextureButton.new()
	button.name = button_name
	button.texture_normal = normal_texture
	button.texture_hover = hover_texture
	button.texture_pressed = hover_texture
	button.texture_focused = hover_texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button

func _layout_menu() -> void:
	if not is_instance_valid(panel):
		return
	var view_size := get_viewport().get_visible_rect().size
	var panel_height: float = minf(view_size.y * 0.92, view_size.x * 0.86 / 0.8)
	var panel_size := Vector2(panel_height * 0.8, panel_height)
	var panel_position := (view_size - panel_size) * 0.5
	panel.position = panel_position
	panel.size = panel_size
	touch_pause_button.position = Vector2(view_size.x - 76.0, 16.0)
	touch_pause_button.size = Vector2(60.0, 60.0)

	title.position = panel_position + Vector2(panel_size.x * 0.1, panel_size.y * 0.12)
	title.size = Vector2(panel_size.x * 0.8, panel_size.y * 0.1)
	title.add_theme_font_size_override("font_size", int(clamp(panel_size.y * 0.07, 26.0, 44.0)))

	var button_size := Vector2(panel_size.x * 0.76, panel_size.x * 0.76 / 5.0)
	var gap := button_size.y * 0.22
	var button_x := panel_position.x + (panel_size.x - button_size.x) * 0.5
	var button_y := panel_position.y + panel_size.y * 0.40
	var buttons: Array[TextureButton] = [continue_button, settings_button, exit_button]
	for index in range(buttons.size()):
		var button: TextureButton = buttons[index]
		button.position = Vector2(button_x, button_y + index * (button_size.y + gap))
		button.size = button_size

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if event is InputEventKey and event.echo:
		return
	if settings_screen and is_instance_valid(settings_screen):
		var settings_back := settings_screen.get_node_or_null("BackButton") as BaseButton
		if settings_screen.has_method("_on_back_pressed") and (not settings_back or not settings_back.disabled):
			settings_screen.call("_on_back_pressed")
	else:
		set_menu_open(not menu_is_open)
	get_viewport().set_input_as_handled()

func set_menu_open(should_open: bool) -> void:
	if settings_screen and is_instance_valid(settings_screen):
		return
	menu_is_open = should_open
	pause_content.visible = should_open
	if touch_pause_button:
		touch_pause_button.visible = not should_open and _is_mobile_controls_active()

func close_menu() -> void:
	set_menu_open(false)

func _on_continue_pressed() -> void:
	close_menu()

func _on_settings_pressed() -> void:
	menu_is_open = true
	pause_content.visible = false
	if touch_pause_button:
		touch_pause_button.visible = false
	settings_screen = SETTINGS_SCENE.instantiate() as Control
	settings_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(settings_screen)

func close_settings() -> void:
	if is_instance_valid(settings_screen):
		settings_screen.queue_free()
	settings_screen = null
	pause_content.visible = true
	visible = true
	menu_is_open = true
	if touch_pause_button:
		touch_pause_button.visible = false

func _is_mobile_controls_active() -> bool:
	var mobile_controls := get_node_or_null("/root/MobileControls")
	return mobile_controls != null and bool(mobile_controls.get("is_mobile_active"))

func _on_exit_pressed() -> void:
	var network_manager := get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_method("leave_game"):
		network_manager.call("leave_game")
	get_tree().change_scene_to_file("res://Menu/MainMenu.tscn")
