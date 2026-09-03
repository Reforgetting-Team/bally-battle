extends Node2D

# ts draws the sharp triangle spikes all around the ball when spiky is popped
# 1px black outline and filled with the bally's color

@export var spike_count: int = 16
@export var base_radius: float = 34.0
@export var max_spike_length: float = 16.0

var spike_length: float = 0.0
var fill_color: Color = Color.WHITE
var tween: Tween = null

func _ready() -> void:
	z_index = 1 # sits between ball body and face
	visible = false

func set_color(col: Color) -> void:
	fill_color = col
	queue_redraw()

func pop_spikes() -> void:
	visible = true
	if tween and tween.is_valid():
		tween.kill()
	tween = create_tween()
	# snappy pop out with bounce
	tween.tween_property(self, "spike_length", max_spike_length, 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func retract_spikes() -> void:
	if tween and tween.is_valid():
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "spike_length", 0.0, 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		visible = false
	)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	if spike_length <= 0.1:
		return

	var angle_step := TAU / float(spike_count)
	var half_base_angle := angle_step * 0.35

	for i in range(spike_count):
		var angle := i * angle_step
		var pt_left := Vector2(cos(angle - half_base_angle), sin(angle - half_base_angle)) * base_radius
		var pt_tip := Vector2(cos(angle), sin(angle)) * (base_radius + spike_length)
		var pt_right := Vector2(cos(angle + half_base_angle), sin(angle + half_base_angle)) * base_radius

		var poly := PackedVector2Array([pt_left, pt_tip, pt_right])
		var colors := PackedColorArray([fill_color, fill_color, fill_color])
		draw_polygon(poly, colors)

		# 1px black outline around the triangle
		var outline := PackedVector2Array([pt_left, pt_tip, pt_right, pt_left])
		draw_polyline(outline, Color.BLACK, 1.0, true)
