extends RefCounted
class_name UITransitions

# Shared "bouncy menu" transition used across all menu screens:
# entrance = start below the screen, overshoot up past resting spot, settle down.
# exit = quick overshoot up, then slide all the way down off the bottom of the screen.
# (menu button polish)

const OVERSHOOT_PX := 18.0
const ANTICIPATION_TIME := 0.12
const ENTRANCE_RISE_TIME := 0.25
const SETTLE_TIME := 0.22
const EXIT_SLIDE_TIME := 0.3
const FADE_IN_TIME := 0.6


static func fade_node_in(node: CanvasItem, duration: float = FADE_IN_TIME) -> void:
	# slow fade-in, no movement at all - used for the Back button
	node.modulate.a = 0.0
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func animate_node_out_up(node: Control, on_complete: Callable) -> void:
	# mirror of animate_node_out but exits off the TOP of the screen instead
	# of the bottom - used for the Back button, which goes against the grain
	var start_y: float = node.position.y
	var offscreen_offset: float = node.get_viewport_rect().size.y

	var tween: Tween = node.create_tween()
	tween.tween_property(node, "position:y", start_y + OVERSHOOT_PX, ANTICIPATION_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:y", start_y - offscreen_offset - OVERSHOOT_PX, EXIT_SLIDE_TIME)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if on_complete.is_valid():
		tween.tween_callback(on_complete)


static func animate_in(root: Node, exclude: Array = []) -> void:
	# animates every direct Control child of root (except anything in exclude)
	animate_in_nodes(_collect_children(root, exclude))


static func animate_out(root: Node, on_complete: Callable, exclude: Array = []) -> void:
	# same, but for leaving a screen
	animate_out_nodes(_collect_children(root, exclude), on_complete)


static func animate_node_in(node: Control) -> void:
	# convenience for a single control (e.g. a standalone button)
	animate_in_nodes([node])


static func animate_node_out(node: Control, on_complete: Callable) -> void:
	animate_out_nodes([node], on_complete)


static func _collect_children(root: Node, exclude: Array) -> Array:
	var kids: Array = []
	for child in root.get_children():
		if exclude.has(child):
			continue
		if child is Control:
			kids.append(child)
	return kids


static func _offscreen_offset(nodes: Array) -> float:
	var ref: Control = nodes[0]
	return ref.get_viewport_rect().size.y


static func animate_in_nodes(nodes: Array) -> void:
	if nodes.is_empty():
		return
	var offscreen_offset: float = _offscreen_offset(nodes)

	for n in nodes:
		var ctrl: Control = n
		var target_y: float = ctrl.position.y
		ctrl.position.y = target_y + offscreen_offset

		var tween: Tween = ctrl.create_tween()
		tween.tween_property(ctrl, "position:y", target_y - OVERSHOOT_PX, ENTRANCE_RISE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(ctrl, "position:y", target_y, SETTLE_TIME).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


static func animate_out_nodes(nodes: Array, on_complete: Callable) -> void:
	if nodes.is_empty():
		on_complete.call()
		return

	var offscreen_offset: float = _offscreen_offset(nodes)
	var start_y: Dictionary = {}
	for n in nodes:
		var ctrl: Control = n
		start_y[ctrl] = ctrl.position.y

	var anchor: Control = nodes[0]
	var tween: Tween = anchor.create_tween()

	var rise_step := func(t: float) -> void:
		for n in nodes:
			var ctrl: Control = n
			ctrl.position.y = start_y[ctrl] - OVERSHOOT_PX * t

	var fall_step := func(t: float) -> void:
		for n in nodes:
			var ctrl: Control = n
			ctrl.position.y = (start_y[ctrl] - OVERSHOOT_PX) + (offscreen_offset + OVERSHOOT_PX) * t

	tween.tween_method(rise_step, 0.0, 1.0, ANTICIPATION_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(fall_step, 0.0, 1.0, EXIT_SLIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(on_complete)
