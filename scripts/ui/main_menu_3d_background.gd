extends Node3D
class_name MainMenu3DBackground

# Rotating camera around a zombie survival scene with animated zombies

@export var rotation_speed: float = 0.1
@export var camera_distance: float = 8.0
@export var camera_height: float = 3.0
@export var look_at_height: float = 1.0
@export var zombie_count: int = 5
@export var zombie_wander_radius: float = 8.0

@onready var camera: Camera3D = $Camera3D
@onready var environment: WorldEnvironment = $WorldEnvironment
@onready var character_display: Node3D = $CharacterDisplay
@onready var zombie_decor: Node3D = $ZombieDecor

var camera_angle: float = 0.0
var target_pos: Vector3 = Vector3.ZERO
var spawned_zombies: Array = []

# Zombie movement data
var zombie_targets: Dictionary = {}
var zombie_speeds: Dictionary = {}

func _ready():
	_setup_environment()
	_spawn_scenery()
	_spawn_menu_zombies()

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

	# Update zombie wandering
	_update_zombies(delta)

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

func _spawn_menu_zombies():
	"""Spawn decorative zombies that wander around the scene"""
	if not zombie_decor:
		zombie_decor = Node3D.new()
		zombie_decor.name = "ZombieDecor"
		add_child(zombie_decor)

	# Try to load zombie models
	var zombie_models = [
		"res://Free_Character/ShowcaseFreeCharacter/Characters/Zombie/male_z.glb",
		"res://Free_Character/ShowcaseFreeCharacter/Characters/Zombie/female_z.glb"
	]

	for i in range(zombie_count):
		var model_path = zombie_models[i % zombie_models.size()]

		if not ResourceLoader.exists(model_path):
			# Create placeholder zombie
			var placeholder = _create_placeholder_zombie()
			_setup_zombie(placeholder, i)
			continue

		var model_scene = load(model_path)
		if model_scene:
			var zombie = model_scene.instantiate()
			_setup_zombie(zombie, i)

func _create_placeholder_zombie() -> Node3D:
	"""Create a simple placeholder if zombie model not found"""
	var zombie = Node3D.new()

	var mesh_inst = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	mesh_inst.mesh = capsule
	mesh_inst.position.y = 0.8

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.4, 0.3)
	mesh_inst.material_override = mat

	zombie.add_child(mesh_inst)
	return zombie

func _setup_zombie(zombie: Node3D, index: int):
	"""Setup zombie position and movement"""
	zombie_decor.add_child(zombie)
	spawned_zombies.append(zombie)

	# Random starting position in circle
	var angle = (float(index) / zombie_count) * TAU + randf() * 0.5
	var dist = randf_range(4.0, zombie_wander_radius)
	zombie.position = Vector3(
		cos(angle) * dist,
		0,
		sin(angle) * dist
	)

	# Random scale variation
	var scale_var = randf_range(0.85, 1.15)
	zombie.scale = Vector3.ONE * scale_var

	# Apply zombie tint
	_apply_zombie_tint(zombie)

	# Setup movement
	zombie_speeds[zombie] = randf_range(0.3, 0.8)
	_set_new_wander_target(zombie)

	# Try to play animation
	_play_walk_animation(zombie)

func _apply_zombie_tint(zombie: Node3D):
	"""Apply grayish-green zombie tint to meshes"""
	for child in zombie.get_children():
		_apply_tint_recursive(child, Color(0.6, 0.7, 0.6))

func _apply_tint_recursive(node: Node, color: Color):
	if node is MeshInstance3D:
		var mesh_inst = node as MeshInstance3D
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				var mat = mesh_inst.get_active_material(i)
				if mat is StandardMaterial3D:
					var new_mat = mat.duplicate()
					new_mat.albedo_color = new_mat.albedo_color * color
					mesh_inst.set_surface_override_material(i, new_mat)

	for child in node.get_children():
		_apply_tint_recursive(child, color)

func _play_walk_animation(zombie: Node3D):
	"""Find and play walk animation on zombie"""
	var anim_player = _find_animation_player(zombie)
	if anim_player:
		var walk_names = ["walk", "Walk", "WALK", "walking", "walk_forward", "shamble", "zombie_walk"]
		for anim_name in walk_names:
			if anim_player.has_animation(anim_name):
				anim_player.play(anim_name)
				anim_player.speed_scale = randf_range(0.5, 1.0)
				return

		# Play first animation if no walk
		var animations = anim_player.get_animation_list()
		if animations.size() > 0:
			anim_player.play(animations[0])
			anim_player.speed_scale = randf_range(0.4, 0.8)

func _set_new_wander_target(zombie: Node3D):
	"""Set a new random target position for zombie to wander to"""
	var angle = randf() * TAU
	var dist = randf_range(3.0, zombie_wander_radius)
	zombie_targets[zombie] = Vector3(
		cos(angle) * dist,
		0,
		sin(angle) * dist
	)

func _update_zombies(delta):
	"""Update zombie wandering movement"""
	for zombie in spawned_zombies:
		if not is_instance_valid(zombie):
			continue

		var target = zombie_targets.get(zombie, Vector3.ZERO)
		var speed = zombie_speeds.get(zombie, 0.5)

		# Move toward target
		var direction = (target - zombie.position).normalized()
		direction.y = 0

		if zombie.position.distance_to(target) > 1.0:
			zombie.position += direction * speed * delta

			# Face movement direction
			if direction.length() > 0.1:
				zombie.look_at(zombie.position + direction, Vector3.UP)
		else:
			# Reached target, set new one
			_set_new_wander_target(zombie)

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
