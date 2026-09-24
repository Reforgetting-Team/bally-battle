extends AudioStreamPlayer

# menu music sticks around between scenes n shuts up during matches
const MENU_SCENE_PREFIXES: Array[String] = [
	"res://Menu/",
]

func _ready() -> void:
	# scene changes decide when music plays, not the built-in autoplay toggle
	autoplay = false
	if stream is AudioStreamWAV:
		# loop the whole clip forever since its just a short music bed
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# loop_end wants a sample frame, 0 would make the clip stop right away
		wav.loop_end = int(wav.get_length() * wav.mix_rate)

	get_tree().node_added.connect(_on_node_added)
	# in case current_scene is already set by the time we connect up
	call_deferred("_sync_to_current_scene")

func _on_node_added(node: Node) -> void:
	# only top-level nodes can be a new scene, n current_scene updates a beat later
	if node.get_parent() == get_tree().root:
		call_deferred("_sync_to_current_scene")

func _sync_to_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _is_menu_scene(scene.scene_file_path):
		if not playing:
			play()
	else:
		if playing:
			stop()

func _is_menu_scene(scene_path: String) -> bool:
	for prefix in MENU_SCENE_PREFIXES:
		if scene_path.begins_with(prefix):
			return true
	return false
