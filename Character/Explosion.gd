extends Node2D

# so ts is the actual boom u see when a bomb pops, cuz before ts existed the
# bomb just silently vanished n u had no clue u even got blown up lol.
# its all drawn in code so we dont gotta make a whole particle scene for it

var radius: float = 90.0

const DURATION: float = 0.3      # whole flash is over quick, bopl's boom doesnt linger
const SHAKE_STRENGTH: float = 14.0
const SHAKE_DURATION: float = 0.26

const BOOM_STREAM: AudioStream = preload("res://Sounds/Pop.ogg")

var _elapsed: float = 0.0

func _ready() -> void:
	z_index = 5

	# reuse the pop sound but pitched way down so it reads as a boom n not a bubble
	var boom := AudioStreamPlayer2D.new()
	boom.stream = BOOM_STREAM
	boom.pitch_scale = 0.45
	boom.volume_db = 4.0
	add_child(boom)
	boom.play()

	# kick the camera a lil, ts is like half of why explosions feel good tbh
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(SHAKE_STRENGTH, SHAKE_DURATION)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clamp(_elapsed / DURATION, 0.0, 1.0)
	# eases out so it snaps open fast then slows down, instead of growing linear n looking fake
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	var fade: float = 1.0 - t

	# outer fireball
	var blast_radius: float = lerp(radius * 0.4, radius * 1.15, eased)
	draw_circle(Vector2.ZERO, blast_radius, Color(1.0, 0.55, 0.15, 0.55 * fade))
	# hot core thats a bit smaller n brighter
	draw_circle(Vector2.ZERO, blast_radius * 0.6, Color(1.0, 0.92, 0.6, 0.75 * fade))
	# thin ring racing outward so u can actually read how far the blast reached
	draw_arc(Vector2.ZERO, blast_radius * 1.05, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.7 * fade), 4.0, true)
