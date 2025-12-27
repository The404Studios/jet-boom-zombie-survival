## AISystem - Processes AI controller logic and pathfinding
## Handles zombie AI, navigation, and behavior state machines
class_name AISystem
extends System

## Priority is slightly higher to run before movement
var priority: int = -5


func get_system_name() -> String:
	return "AISystem"


func get_required_components() -> Array[String]:
	return ["Controller", "Transform"]


func get_optional_components() -> Array[String]:
	return ["Navigation", "Velocity", "Health"]


func process_entity(entity: Entity, delta: float) -> void:
	var controller_comp := entity.get_component("Controller") as ControllerComponent
	if not controller_comp or not controller_comp.enabled:
		return

	# Update controller
	controller_comp.update(delta)

	# Handle specific AI controllers
	if controller_comp is ZombieControllerComponent:
		_process_zombie_ai(entity, controller_comp as ZombieControllerComponent, delta)
	elif controller_comp is ProjectileControllerComponent:
		_process_projectile(entity, controller_comp as ProjectileControllerComponent, delta)


## Process zombie AI
func _process_zombie_ai(entity: Entity, zombie_ctrl: ZombieControllerComponent, delta: float) -> void:
	var transform_comp := entity.get_component("Transform") as TransformComponent
	var nav_comp := entity.get_component("Navigation") as NavigationComponent

	if not transform_comp:
		return

	# Update navigation if available
	if nav_comp and zombie_ctrl.target_entity:
		nav_comp.set_target_entity(zombie_ctrl.target_entity)
		nav_comp.update_navigation(delta, transform_comp.position)

		# Use navigation direction if navigating
		if nav_comp.is_navigating and not nav_comp.is_navigation_complete():
			var nav_direction := nav_comp.get_next_direction(transform_comp.position)
			if nav_direction.length() > 0.1:
				zombie_ctrl.input_direction = nav_direction

		# Set avoidance velocity for RVO
		var velocity_comp := entity.get_component("Velocity") as VelocityComponent
		if velocity_comp:
			nav_comp.set_avoidance_velocity(velocity_comp.linear)

	# Update animations based on state
	_update_zombie_animation(entity, zombie_ctrl)


## Update zombie animation based on AI state
func _update_zombie_animation(entity: Entity, zombie_ctrl: ZombieControllerComponent) -> void:
	var model_comp := entity.get_component("Model") as ModelComponent
	if not model_comp:
		return

	var anim_name := ""
	match zombie_ctrl.ai_state:
		ZombieControllerComponent.ZombieState.IDLE:
			anim_name = zombie_ctrl.anim_idle
		ZombieControllerComponent.ZombieState.WANDER:
			anim_name = zombie_ctrl.anim_walk
		ZombieControllerComponent.ZombieState.CHASE:
			anim_name = zombie_ctrl.anim_run if zombie_ctrl.is_enraged else zombie_ctrl.anim_walk
		ZombieControllerComponent.ZombieState.ATTACK:
			anim_name = zombie_ctrl.anim_attack
		ZombieControllerComponent.ZombieState.STUNNED:
			anim_name = zombie_ctrl.anim_hurt
		ZombieControllerComponent.ZombieState.DYING, ZombieControllerComponent.ZombieState.DEAD:
			anim_name = zombie_ctrl.anim_death

	if anim_name != "" and model_comp.current_animation != anim_name:
		if model_comp.has_animation(anim_name):
			model_comp.play_animation(anim_name)


## Process projectile controller
func _process_projectile(entity: Entity, projectile_ctrl: ProjectileControllerComponent,
		_delta: float) -> void:

	if not projectile_ctrl.is_active():
		return

	var transform_comp := entity.get_component("Transform") as TransformComponent
	var collider_comp := entity.get_component("Collider") as ColliderComponent

	if not transform_comp:
		return

	# Check for hits using raycast or area
	if collider_comp:
		if collider_comp.area:
			# Check area overlaps
			for body in collider_comp.overlapping_bodies:
				if _is_valid_projectile_target(body, projectile_ctrl):
					projectile_ctrl.on_hit(body, transform_comp.position)
					break


## Check if a body is a valid projectile target
func _is_valid_projectile_target(body: Node3D, projectile_ctrl: ProjectileControllerComponent) -> bool:
	# Check ignore tags
	if body is Entity:
		var target_entity := body as Entity
		for tag in projectile_ctrl.ignore_tags:
			if target_entity.has_tag(tag):
				return false

		# Don't hit source
		if projectile_ctrl.source_entity and target_entity == projectile_ctrl.source_entity:
			return false

	return true


## Find nearest target for an AI entity
func find_nearest_target(entity: Entity, tag: String, max_distance: float = -1) -> Entity:
	if not world:
		return null

	var transform_comp := entity.get_component("Transform") as TransformComponent
	if not transform_comp:
		return null

	var targets := world.get_entities_with_tag(tag)
	var nearest: Entity = null
	var nearest_dist := INF

	for target in targets:
		if target == entity:
			continue

		var target_transform := target.get_component("Transform") as TransformComponent
		if not target_transform:
			continue

		var dist := transform_comp.position.distance_to(target_transform.position)
		if dist < nearest_dist:
			if max_distance < 0 or dist <= max_distance:
				nearest = target
				nearest_dist = dist

	return nearest


## Get all targets within range
func get_targets_in_range(entity: Entity, tag: String, range_distance: float) -> Array[Entity]:
	var result: Array[Entity] = []

	if not world:
		return result

	var transform_comp := entity.get_component("Transform") as TransformComponent
	if not transform_comp:
		return result

	var targets := world.get_entities_with_tag(tag)
	for target in targets:
		if target == entity:
			continue

		var target_transform := target.get_component("Transform") as TransformComponent
		if not target_transform:
			continue

		var dist := transform_comp.position.distance_to(target_transform.position)
		if dist <= range_distance:
			result.append(target)

	return result
