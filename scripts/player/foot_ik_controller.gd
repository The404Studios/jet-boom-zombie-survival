extends Node3D

# Simple foot IK system for visible feet in first-person
# Uses raycasts to detect ground and adjust foot position

@export var foot_offset: float = 0.4  # Distance from center to each foot
@export var step_height: float = 0.3
@export var step_distance: float = 0.8
@export var step_speed: float = 10.0

var left_foot_pos: Vector3 = Vector3.ZERO
var right_foot_pos: Vector3 = Vector3.ZERO
var left_foot_target: Vector3 = Vector3.ZERO
var right_foot_target: Vector3 = Vector3.ZERO
var is_left_moving: bool = false
var is_right_moving: bool = false
var last_body_pos: Vector3 = Vector3.ZERO

@onready var player: CharacterBody3D = get_parent().get_parent() if get_parent() else null
@onready var left_foot_mesh: MeshInstance3D = $LeftFoot if has_node("LeftFoot") else null
@onready var right_foot_mesh: MeshInstance3D = $RightFoot if has_node("RightFoot") else null
@onready var left_raycast: RayCast3D = $LeftRaycast if has_node("LeftRaycast") else null
@onready var right_raycast: RayCast3D = $RightRaycast if has_node("RightRaycast") else null

func _ready():
	_setup_feet()
	_setup_raycasts()
	last_body_pos = player.global_position if player else global_position

func _setup_feet():
	"""Create simple foot meshes"""
	if not left_foot_mesh:
		left_foot_mesh = MeshInstance3D.new()
		add_child(left_foot_mesh)
		left_foot_mesh.name = "LeftFoot"
		var mesh = BoxMesh.new()
		mesh.size = Vector3(0.15, 0.08, 0.25)
		left_foot_mesh.mesh = mesh
		left_foot_mesh.position = Vector3(-foot_offset, -0.9, 0)

	if not right_foot_mesh:
		right_foot_mesh = MeshInstance3D.new()
		add_child(right_foot_mesh)
		right_foot_mesh.name = "RightFoot"
		var mesh = BoxMesh.new()
		mesh.size = Vector3(0.15, 0.08, 0.25)
		right_foot_mesh.mesh = mesh
		right_foot_mesh.position = Vector3(foot_offset, -0.9, 0)

	# Initialize positions
	left_foot_pos = left_foot_mesh.position
	right_foot_pos = right_foot_mesh.position
	left_foot_target = left_foot_pos
	right_foot_target = right_foot_pos

func _setup_raycasts():
	"""Setup raycasts for ground detection"""
	if not left_raycast:
		left_raycast = RayCast3D.new()
		add_child(left_raycast)
		left_raycast.name = "LeftRaycast"
		left_raycast.target_position = Vector3(0, -2, 0)
		left_raycast.enabled = true

	if not right_raycast:
		right_raycast = RayCast3D.new()
		add_child(right_raycast)
		right_raycast.name = "RightRaycast"
		right_raycast.target_position = Vector3(0, -2, 0)
		right_raycast.enabled = true

func _physics_process(delta):
	if not player:
		return

	var velocity_2d = Vector2(player.velocity.x, player.velocity.z)
	var is_moving = velocity_2d.length() > 0.1

	if is_moving:
		_update_stepping(delta)
	else:
		_update_idle(delta)

	# Update raycast positions
	if left_raycast:
		left_raycast.global_position = player.global_position + Vector3(-foot_offset, 0, 0)
	if right_raycast:
		right_raycast.global_position = player.global_position + Vector3(foot_offset, 0, 0)

	# Smooth foot movement
	left_foot_pos = left_foot_pos.lerp(left_foot_target, delta * step_speed)
	right_foot_pos = right_foot_pos.lerp(right_foot_target, delta * step_speed)

	# Apply to meshes
	if left_foot_mesh:
		left_foot_mesh.position = left_foot_pos
	if right_foot_mesh:
		right_foot_mesh.position = right_foot_pos

	last_body_pos = player.global_position

func _update_stepping(delta):
	"""Handle foot stepping when moving"""
	var move_delta = player.global_position - last_body_pos
	var move_distance = Vector2(move_delta.x, move_delta.z).length()

	# Check if we need to step
	if not is_left_moving and not is_right_moving:
		# Determine which foot to move
		var left_dist = Vector2(left_foot_target.x, left_foot_target.z).distance_to(
			Vector2(player.global_position.x - foot_offset, player.global_position.z))
		var right_dist = Vector2(right_foot_target.x, right_foot_target.z).distance_to(
			Vector2(player.global_position.x + foot_offset, player.global_position.z))

		if left_dist > step_distance:
			_step_foot(true)
		elif right_dist > step_distance:
			_step_foot(false)

func _step_foot(is_left: bool):
	"""Move a foot to new position"""
	if is_left:
		is_left_moving = true
		var target_pos = player.global_position + Vector3(-foot_offset, 0, 0.3)

		# Raycast to find ground
		if left_raycast and left_raycast.is_colliding():
			var hit_y = left_raycast.get_collision_point().y
			left_foot_target = Vector3(-foot_offset, hit_y - player.global_position.y + 0.04, 0.3)
		else:
			left_foot_target = Vector3(-foot_offset, -0.9, 0.3)

		await get_tree().create_timer(0.15).timeout
		is_left_moving = false
	else:
		is_right_moving = true
		var target_pos = player.global_position + Vector3(foot_offset, 0, 0.3)

		# Raycast to find ground
		if right_raycast and right_raycast.is_colliding():
			var hit_y = right_raycast.get_collision_point().y
			right_foot_target = Vector3(foot_offset, hit_y - player.global_position.y + 0.04, 0.3)
		else:
			right_foot_target = Vector3(foot_offset, -0.9, 0.3)

		await get_tree().create_timer(0.15).timeout
		is_right_moving = false

func _update_idle(delta):
	"""Handle foot position when idle"""
	# Smoothly return to default stance
	left_foot_target = left_foot_target.lerp(Vector3(-foot_offset, -0.9, 0), delta * 2.0)
	right_foot_target = right_foot_target.lerp(Vector3(foot_offset, -0.9, 0), delta * 2.0)

	# Apply ground detection
	if left_raycast and left_raycast.is_colliding():
		var hit_y = left_raycast.get_collision_point().y
		left_foot_target.y = hit_y - player.global_position.y + 0.04

	if right_raycast and right_raycast.is_colliding():
		var hit_y = right_raycast.get_collision_point().y
		right_foot_target.y = hit_y - player.global_position.y + 0.04
