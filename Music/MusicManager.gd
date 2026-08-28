extends AudioStreamPlayer

# Global menu music. Autoloaded as "Music" so it survives scene changes.
#
# Scenes under these path prefixes get music playing automatically.
# Anything else (the actual gameplay Areas, etc.) gets it stopped.
# Add new menu scenes' folders here if you add more later.
const MENU_SCENE_PREFIXES: Array[String] = [
	"res://Menu/",
]

func _ready() -> void:
	# we drive play/stop ourselves based on which scene is active,
	# so we don't want the node's own autoplay racing us
	autoplay = false
	if stream is AudioStreamWAV:
		# loop the whole clip forever, since it's a short music bed
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = 0  # 0 = loop to the end of the sample data

	get_tree().node_added.connect(_on_node_added)
	# in case current_scene is already set by the time we connect
	call_deferred("_sync_to_current_scene")

func _on_node_added(node: Node) -> void:
	# fires for every node in the game, so keep this check cheap;
	# we only care about the moment a new top-level scene is added
	# directly under the tree root. We defer the actual sync because
	# SceneTree.current_scene isn't reliably updated yet at the exact
	# moment this signal fires (it can lag by a frame during initial
	# boot and during change_scene_to_file) -- that lag was why the
	# menu music never started automatically.
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
