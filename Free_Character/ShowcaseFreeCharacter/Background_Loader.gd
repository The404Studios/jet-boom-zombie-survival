extends Node

var loader
var wait_frames
var time_max = 100
var current_scene

#onready var bg_load = $Control/LoadingColor
#onready var bg_go = $Control/GameOverColor


func _ready():
	set_process(false)
	var tmp_root = get_tree().get_root()
	current_scene = tmp_root.get_child(tmp_root.get_child_count() - 1)
	#bg_load.visible = false
	#bg_go.visible = false
	
#func goto_scene(path, gOver = false):
func goto_scene(path):
	loader = ResourceLoader.load_interactive(path)
	if(loader == null):
		print("error load from Reasource Loader :p")
		return
	set_process(true)
	
	current_scene.queue_free()
	#bg_load.visible = true
	#start your "loading..." animation
	#if gOver:
	#	bg_go.visible = true
	#else:
	#	bg_load.visible = true
	wait_frames = 100
	
func _process(_delta):
	if(loader == null):
		set_process(false)
		return
	
	if(wait_frames > 0):
		wait_frames -= 1
		return
		
	var t = OS.get_ticks_msec()
	while(OS.get_ticks_msec() < t + time_max):
		var err = loader.poll()
		
		if(err == ERR_FILE_EOF): #load finished
			var resource = loader.get_resource()
			loader = null
			set_new_scene(resource)
			break
		elif(err == OK):
			#update_progress()
			pass
		else:
			print("error while loading resource!! ;p")
			loader = null
			break
		
#func update_progress():
#	var _progress = float(loader.get_stage()) / loader.get_stage_count()
#	_tmpInt = int(_progress * 100)
#	tex_progress.value = _tmpInt
#
#	progress_label.set_text(String(_tmpInt) + "%")
		
func set_new_scene(scene_resource):
	var tmp_root = get_tree().get_root()
	current_scene = scene_resource.instance()
	tmp_root.add_child(current_scene)
	#bg_load.visible = false
	#bg_go.visible = false
	
