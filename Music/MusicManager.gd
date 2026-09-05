extends AudioStreamPlayer

# global menu music, autoloaded as "Music" so it survives scene changes n stuff
#
# scenes under these path prefixes get the music playing automatically
# anything else (the actual gameplay Areas etc) gets it stopped
# add new menu scene folders here if u add more later ig
const MENU_SCENE_PREFIXES: Array[String] = [
	"res://Menu/",
]

func _ready() -> void:
	# we drive play/stop ourselves based on whatever scene is active rn,
	# so we dont want the node's own autoplay racing us n causing weirdness
	autoplay = false
	if stream is AudioStreamWAV:
		# loop the whole clip forever since its just a short music bed
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# loop_end is a SAMPLE FRAME INDEX, not some sentinel value, so 0
		# means "loop the first zero frames" (aka play nothing n stop
		# immediately), NOT "loop to the end" like u'd think. thats literally
		# why the music never audibly played, play() succeeded for like one
		# frame then instantly stopped lol. gotta compute the real frame
		# count from the stream's actual length instead
		wav.loop_end = int(wav.get_length() * wav.mix_rate)

	get_tree().node_added.connect(_on_node_added)
	# in case current_scene is already set by the time we connect up
	call_deferred("_sync_to_current_scene")

func _on_node_added(node: Node) -> void:
	# this fires for literally every node in the game so keep it cheap,
	# we only care about the moment a new top level scene gets added
	# directly under the tree root. we defer the actual sync bc
	# SceneTree.current_scene isnt reliably updated yet at the exact
	# moment this signal fires (it can lag during initial boot n during
	# change_scene_to_file, learned that one the hard way)
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
