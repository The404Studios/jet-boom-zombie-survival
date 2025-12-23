extends Node

@export var target_fps: int = 144

func _ready():
	Engine.max_fps = target_fps
	# Disable vsync for precise FPS control
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _process(_delta):
	# Display FPS for debugging
	if OS.is_debug_build():
		var fps = Engine.get_frames_per_second()
		if fps > 0:
			DisplayServer.window_set_title("Zombie Survival | FPS: %d" % fps)
