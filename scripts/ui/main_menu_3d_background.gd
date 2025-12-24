extends Node3D
class_name MainMenu3DBackground

# Rotating camera around a zombie survival scene

@export var rotation_speed: float = 0.1
@export var camera_distance: float = 8.0
@export var camera_height: float = 3.0
@export var look_at_height: float = 1.0

@onready var camera: Camera3D = $Camera3D
@onready var environment: WorldEnvironment = $WorldEnvironment
@onready var character_display: Node3D = $CharacterDisplay

var camera_angle: float = 0.0
var target_pos: Vector3 = Vector3.ZERO

func _ready():
	_setup_environment()
	_spawn_scenery()

func _process(delta):
	# Rotate camera
	camera_angle += delta * rotation_speed
	if camera_angle > TAU:
		camera_angle -= TAU

	# Update camera position
	var x = cos(camera_angle) * camera_distance
	var z = sin(camera_angle) * camera_distance
	camera.position = Vector3(x, camera_height, z)
	camera.look_at(Vector3(0, look_at_height, 0), Vector3.UP)

func _setup_environment():
	if not environment or not environment.environment:
		return

	# Apply atmospheric effects
	var env = environment.environment
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.25, 0.35)
	env.fog_density = 0.02
	env.volumetric_fog_enabled = false  # Too heavy for menu

func _spawn_scenery():
	# This is called at ready - scenery is set up in the scene file
	pass

func set_character_model(model_path: String):
	# Clear existing character
	for child in character_display.get_children():
		child.queue_free()

	# Load and display new character
	if ResourceLoader.exists(model_path):
		var model = load(model_path).instantiate()
		character_display.add_child(model)
		_play_idle_animation(model)

func _play_idle_animation(model: Node3D):
	var anim_player = _find_animation_player(model)
	if anim_player:
		var idle_names = ["idle", "Idle", "IDLE", "idle_loop", "stand", "breathing"]
		for anim_name in idle_names:
			if anim_player.has_animation(anim_name):
				anim_player.play(anim_name)
				return
		# Play first animation if no idle
		var animations = anim_player.get_animation_list()
		if animations.size() > 0:
			anim_player.play(animations[0])

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null
