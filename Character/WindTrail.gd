extends Node2D

# ts like makes the curved wind trail thing work or sum
# tracks where the ball was so the lines actually curve instead of looking goofy

@onready var line_top: Line2D = $LineTop
@onready var line_mid: Line2D = $LineMid
@onready var line_bot: Line2D = $LineBot

var target_node: CharacterBody2D = null
var is_active: bool = false
var history: Array = []
var fade_tween: Tween = null

# keep points alive long enough so the trail doesnt just vanish mid dash
const MAX_POINTS: int = 45
const POINT_LIFETIME: float = 0.35
const SPACING: float = 16.0 # how far apart the three lines chill from each other

func _ready() -> void:
	# draw in world space so the curves dont spin around with the ball
	top_level = true
	# z_index 1 puts it in front of ground tiles (z=0) n behind the ball sprite (z=2)
	z_index = 1
	_setup_lines()

func _setup_lines() -> void:
	# style the lines w that clean anime speed lines vibe
	var lines = [line_top, line_mid, line_bot]
	for line in lines:
		if not line:
			continue
		line.width = 5.0
		line.antialiased = true
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.default_color = Color(1.0, 1.0, 1.0, 0.75)
		
		# start of the line (the tail) fades in smooth from 0 to 75% opacity
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
		grad.set_offset(0, 0.0)
		grad.add_point(0.35, Color(1.0, 1.0, 1.0, 0.75))
		grad.add_point(1.0, Color(1.0, 1.0, 1.0, 0.75))
		line.gradient = grad

func start_trail(target: CharacterBody2D) -> void:
	target_node = target
	is_active = true
	visible = true
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	modulate.a = 1.0

func stop_trail() -> void:
	is_active = false
	# fade it out smooth so it doesnt just snap out of existence lol
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.22)
	fade_tween.tween_callback(func():
		if not is_active:
			visible = false
			history.clear()
			if line_top: line_top.clear_points()
			if line_mid: line_mid.clear_points()
			if line_bot: line_bot.clear_points()
	)

func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	# record positions while dashing so the lines follow ur sick curves
	if is_active and is_instance_valid(target_node):
		var pos = target_node.global_position
		var vel = target_node.velocity
		var normal = Vector2.UP
		if vel.length_squared() > 16.0:
			normal = Vector2(-vel.y, vel.x).normalized()
			if normal.y > 0.0:
				normal = -normal

		# push a new point when we actually move
		if history.is_empty() or history[0].pos.distance_squared_to(pos) > 16.0:
			history.push_front({
				"pos": pos,
				"normal": normal,
				"time": now
			})
		else:
			# smoothly update the current head point so the trail stays glued to the ball
			history[0].pos = pos
			history[0].normal = normal
			history[0].time = now

	# prune old points that already lived their best life
	while not history.is_empty() and (now - history.back().time > POINT_LIFETIME or history.size() > MAX_POINTS):
		history.pop_back()

	if history.size() < 2:
		if line_top: line_top.clear_points()
		if line_mid: line_mid.clear_points()
		if line_bot: line_bot.clear_points()
		if not is_active:
			visible = false
		return

	visible = true

	# stagger the line lengths a lil bit so it actually looks like wind n not just lines
	var mid_count = history.size()
	var top_count = max(2, int(mid_count * 0.88))
	var bot_count = max(2, int(mid_count * 0.94))

	var pts_mid := PackedVector2Array()
	var pts_top := PackedVector2Array()
	var pts_bot := PackedVector2Array()

	pts_mid.resize(mid_count)
	for i in range(mid_count):
		pts_mid[i] = history[mid_count - 1 - i].pos

	pts_top.resize(top_count)
	for i in range(top_count):
		var pt = history[top_count - 1 - i]
		pts_top[i] = pt.pos + pt.normal * SPACING

	pts_bot.resize(bot_count)
	for i in range(bot_count):
		var pt = history[bot_count - 1 - i]
		pts_bot[i] = pt.pos - pt.normal * SPACING

	if line_mid: line_mid.points = pts_mid
	if line_top: line_top.points = pts_top
	if line_bot: line_bot.points = pts_bot
