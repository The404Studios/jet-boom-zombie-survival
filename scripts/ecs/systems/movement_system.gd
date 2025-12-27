## MovementSystem - Processes entity movement based on velocity and transform
## Handles physics-based movement for CharacterBody3D entities
class_name MovementSystem
extends System

## Gravity constant
var gravity: float = 20.0

## Ground snap distance
var snap_distance: float = 0.1


func get_system_name() -> String:
	return "MovementSystem"


func get_required_components() -> Array[String]:
	return ["Transform", "Velocity"]


func get_optional_components() -> Array[String]:
	return ["Collider", "Controller"]


func physics_process_entity(entity: Entity, delta: float) -> void:
	var transform_comp := entity.get_component("Transform") as TransformComponent
	var velocity_comp := entity.get_component("Velocity") as VelocityComponent
	var collider_comp := entity.get_component("Collider") as ColliderComponent
	var controller_comp := entity.get_component("Controller") as ControllerComponent

	if not transform_comp or not velocity_comp:
		return

	# Get movement direction from controller
	var move_direction := Vector3.ZERO
	var move_speed := velocity_comp.max_speed

	if controller_comp and controller_comp.enabled:
		move_direction = controller_comp.input_direction

		# Get speed from specific controller types
		if controller_comp is PlayerControllerComponent:
			move_speed = (controller_comp as PlayerControllerComponent).get_movement_speed()
		elif controller_comp is ZombieControllerComponent:
			move_speed = (controller_comp as ZombieControllerComponent).get_current_speed()
		elif controller_comp is ProjectileControllerComponent:
			move_speed = (controller_comp as ProjectileControllerComponent).speed

	# Calculate target horizontal velocity
	var target_velocity := move_direction * move_speed

	# Accelerate or decelerate toward target
	var horizontal := velocity_comp.get_horizontal_velocity()
	if target_velocity.length() > 0.1:
		horizontal = horizontal.move_toward(target_velocity, velocity_comp.acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, velocity_comp.deceleration * delta)

	velocity_comp.set_horizontal_velocity(horizontal)

	# Apply gravity
	if velocity_comp.use_gravity:
		velocity_comp.linear.y -= gravity * velocity_comp.gravity_scale * delta

	# Handle jump (for player controller)
	if controller_comp is PlayerControllerComponent:
		var player_ctrl := controller_comp as PlayerControllerComponent
		if player_ctrl.action_jump and velocity_comp.is_grounded:
			velocity_comp.linear.y = player_ctrl.jump_velocity

	# Apply friction
	velocity_comp.apply_friction(delta)

	# Move the entity
	if collider_comp and collider_comp.character_body:
		_move_character_body(collider_comp.character_body, velocity_comp, transform_comp, delta)
	else:
		_move_simple(transform_comp, velocity_comp, delta)

	# Update rotation based on look direction
	if controller_comp:
		_apply_rotation(transform_comp, controller_comp, entity)


## Move using CharacterBody3D physics
func _move_character_body(body: CharacterBody3D, velocity_comp: VelocityComponent,
		transform_comp: TransformComponent, _delta: float) -> void:

	body.velocity = velocity_comp.linear
	body.move_and_slide()

	# Update velocity from physics result
	velocity_comp.linear = body.velocity
	velocity_comp.is_grounded = body.is_on_floor()

	# Sync transform from body
	transform_comp.previous_position = transform_comp.position
	transform_comp.position = body.global_position


## Move without physics (simple translation)
func _move_simple(transform_comp: TransformComponent, velocity_comp: VelocityComponent,
		delta: float) -> void:

	transform_comp.previous_position = transform_comp.position
	transform_comp.position += velocity_comp.linear * delta

	# Apply angular velocity
	transform_comp.previous_rotation = transform_comp.rotation
	transform_comp.rotation += velocity_comp.angular * delta


## Apply rotation from controller look direction
func _apply_rotation(transform_comp: TransformComponent, controller_comp: ControllerComponent,
		entity: Entity) -> void:

	if controller_comp is PlayerControllerComponent:
		# Player rotation is handled by camera
		var player_ctrl := controller_comp as PlayerControllerComponent
		transform_comp.rotation.y = player_ctrl.camera_yaw
		player_ctrl.apply_camera_rotation()
	elif controller_comp.look_direction.length() > 0.1:
		# AI entities rotate to face look direction
		var look_dir := controller_comp.look_direction
		look_dir.y = 0

		if look_dir.length() > 0.1:
			var target_rotation := Vector3(
				0,
				atan2(-look_dir.x, -look_dir.z),
				0
			)

			# Smooth rotation for AI
			transform_comp.rotation.y = lerp_angle(
				transform_comp.rotation.y,
				target_rotation.y,
				10.0 * get_physics_process_delta_time()
			)

	# Sync rotation to node if linked
	if transform_comp.node_3d:
		transform_comp.sync_to_node()


## Get physics delta time
func get_physics_process_delta_time() -> float:
	if world:
		return world.get_physics_process_delta_time()
	return 1.0 / 60.0
