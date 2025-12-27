## CombatSystem - Processes weapon firing and combat interactions
## Handles raycasting, damage dealing, and projectile spawning
class_name CombatSystem
extends System

## Priority runs before movement
var priority: int = -10

## Raycast for weapon hit detection
var weapon_raycast: RayCast3D = null

## Signal when weapon fired
signal weapon_fired(entity: Entity, weapon: WeaponComponent)

## Signal when target hit
signal target_hit(attacker: Entity, target: Entity, damage: float, is_crit: bool)

## Reference to world for projectile spawning
var projectile_factory: Callable


func get_system_name() -> String:
	return "CombatSystem"


func get_required_components() -> Array[String]:
	return ["Controller", "Weapon"]


func get_optional_components() -> Array[String]:
	return ["Transform"]


func _on_added() -> void:
	# Create raycast for hit detection
	if world:
		weapon_raycast = RayCast3D.new()
		weapon_raycast.enabled = false
		weapon_raycast.collision_mask = 6  # Zombies and player layers
		world.add_child(weapon_raycast)


func _on_removed() -> void:
	if weapon_raycast and is_instance_valid(weapon_raycast):
		weapon_raycast.queue_free()


func process_entity(entity: Entity, delta: float) -> void:
	var controller_comp := entity.get_component("Controller") as ControllerComponent
	var weapon_comp := entity.get_component("Weapon") as WeaponComponent

	if not controller_comp or not weapon_comp:
		return

	# Update weapon state
	weapon_comp.update(delta)

	# Handle reload input
	if controller_comp.action_reload and weapon_comp.can_reload():
		weapon_comp.start_reload()

	# Handle fire input
	if controller_comp.action_primary:
		if weapon_comp.is_automatic or not _was_firing_last_frame(entity):
			_try_fire_weapon(entity, controller_comp, weapon_comp)


## Track firing state for semi-auto weapons
var _firing_state: Dictionary = {}

func _was_firing_last_frame(entity: Entity) -> bool:
	return _firing_state.get(entity.id, false)


func _on_entity_added(entity: Entity) -> void:
	_firing_state[entity.id] = false


func _on_entity_removed(entity: Entity) -> void:
	_firing_state.erase(entity.id)


func physics_process_entity(entity: Entity, _delta: float) -> void:
	# Track firing state for semi-auto
	var controller_comp := entity.get_component("Controller") as ControllerComponent
	if controller_comp:
		_firing_state[entity.id] = controller_comp.action_primary


## Try to fire the weapon
func _try_fire_weapon(entity: Entity, controller_comp: ControllerComponent,
		weapon_comp: WeaponComponent) -> void:

	if not weapon_comp.try_fire():
		# Auto-reload if empty
		if weapon_comp.is_magazine_empty() and weapon_comp.can_reload():
			weapon_comp.start_reload()
		return

	weapon_fired.emit(entity, weapon_comp)

	# Get firing direction
	var transform_comp := entity.get_component("Transform") as TransformComponent
	if not transform_comp:
		return

	var fire_direction := controller_comp.look_direction
	var fire_origin := transform_comp.position + weapon_comp.muzzle_offset

	# Adjust origin for player camera
	if controller_comp is PlayerControllerComponent:
		var player_ctrl := controller_comp as PlayerControllerComponent
		if player_ctrl.camera:
			fire_origin = player_ctrl.camera.global_position
			fire_direction = -player_ctrl.camera.global_transform.basis.z

	# Fire based on weapon type
	match weapon_comp.weapon_type:
		WeaponComponent.WeaponType.MELEE:
			_fire_melee(entity, fire_origin, fire_direction, weapon_comp)
		WeaponComponent.WeaponType.SHOTGUN:
			_fire_shotgun(entity, fire_origin, fire_direction, weapon_comp)
		WeaponComponent.WeaponType.EXPLOSIVE:
			_fire_projectile(entity, fire_origin, fire_direction, weapon_comp)
		_:
			_fire_hitscan(entity, fire_origin, fire_direction, weapon_comp)


## Fire a hitscan weapon (instant hit)
func _fire_hitscan(entity: Entity, origin: Vector3, direction: Vector3,
		weapon_comp: WeaponComponent) -> void:

	if not weapon_raycast:
		return

	# Apply spread
	var final_direction := weapon_comp.get_spread_direction(direction)

	# Setup raycast
	weapon_raycast.global_position = origin
	weapon_raycast.target_position = final_direction * weapon_comp.weapon_range
	weapon_raycast.force_raycast_update()

	if weapon_raycast.is_colliding():
		var hit_target := weapon_raycast.get_collider()
		var hit_position := weapon_raycast.get_collision_point()

		_process_hit(entity, hit_target, hit_position, weapon_comp)


## Fire a shotgun (multiple pellets)
func _fire_shotgun(entity: Entity, origin: Vector3, direction: Vector3,
		weapon_comp: WeaponComponent) -> void:

	if not weapon_raycast:
		return

	for i in range(weapon_comp.pellet_count):
		var pellet_direction := weapon_comp.get_spread_direction(direction)

		weapon_raycast.global_position = origin
		weapon_raycast.target_position = pellet_direction * weapon_comp.weapon_range
		weapon_raycast.force_raycast_update()

		if weapon_raycast.is_colliding():
			var hit_target := weapon_raycast.get_collider()
			var hit_position := weapon_raycast.get_collision_point()

			# Reduce damage per pellet
			var pellet_damage := weapon_comp.damage / weapon_comp.pellet_count
			_process_hit(entity, hit_target, hit_position, weapon_comp, pellet_damage)


## Fire a melee attack
func _fire_melee(entity: Entity, origin: Vector3, direction: Vector3,
		weapon_comp: WeaponComponent) -> void:

	# Melee uses shorter range raycast or sphere check
	if not weapon_raycast:
		return

	weapon_raycast.global_position = origin
	weapon_raycast.target_position = direction * weapon_comp.weapon_range
	weapon_raycast.force_raycast_update()

	if weapon_raycast.is_colliding():
		var hit_target := weapon_raycast.get_collider()
		var hit_position := weapon_raycast.get_collision_point()

		_process_hit(entity, hit_target, hit_position, weapon_comp)


## Fire a projectile
func _fire_projectile(entity: Entity, origin: Vector3, direction: Vector3,
		weapon_comp: WeaponComponent) -> void:

	if not world or not projectile_factory.is_valid():
		return

	# Create projectile entity via factory
	var projectile_data := {
		"origin": origin,
		"direction": weapon_comp.get_spread_direction(direction),
		"speed": 30.0,  # Projectile speed
		"damage": weapon_comp.damage,
		"source": entity,
		"explosion_radius": 3.0 if weapon_comp.weapon_type == WeaponComponent.WeaponType.EXPLOSIVE else 0.0,
		"explosion_damage": weapon_comp.damage * 1.5
	}

	projectile_factory.call(projectile_data)


## Process a hit
func _process_hit(attacker: Entity, hit_target: Node, hit_position: Vector3,
		weapon_comp: WeaponComponent, override_damage: float = -1) -> void:

	# Calculate damage
	var damage_info := weapon_comp.calculate_damage()
	var final_damage: float = override_damage if override_damage >= 0 else damage_info["damage"]
	var is_crit: bool = damage_info["is_crit"]

	# Try to deal damage to entity
	if hit_target is CharacterBody3D:
		var target_entity := _find_entity_for_node(hit_target)
		if target_entity:
			var health_comp := target_entity.get_component("Health") as HealthComponent
			if health_comp:
				health_comp.take_damage(final_damage, attacker)
				weapon_comp.hit.emit(hit_target, final_damage, is_crit)
				target_hit.emit(attacker, target_entity, final_damage, is_crit)

				# Apply knockback
				if weapon_comp.knockback > 0:
					_apply_knockback(target_entity, hit_position, weapon_comp.knockback)

				# Apply status effect
				if weapon_comp.status_effect != "" and randf() < weapon_comp.status_effect_chance:
					var status_comp := target_entity.get_component("StatusEffect") as StatusEffectComponent
					if status_comp:
						status_comp.apply_effect(
							weapon_comp.status_effect,
							"dot",
							weapon_comp.status_effect_duration,
							final_damage * 0.1
						)
				return

	# Fallback: try direct damage method on node
	if hit_target.has_method("take_damage"):
		hit_target.take_damage(final_damage)


## Find entity that owns a node
func _find_entity_for_node(node: Node) -> Entity:
	if not world:
		return null

	# Check if node is linked to an entity transform
	for entity in world.get_all_entities():
		var transform_comp := entity.get_component("Transform") as TransformComponent
		if transform_comp and transform_comp.node_3d == node:
			return entity

		# Also check collider body
		var collider_comp := entity.get_component("Collider") as ColliderComponent
		if collider_comp and collider_comp.character_body == node:
			return entity

	return null


## Apply knockback to target
func _apply_knockback(target: Entity, from_position: Vector3, force: float) -> void:
	var transform_comp := target.get_component("Transform") as TransformComponent
	var velocity_comp := target.get_component("Velocity") as VelocityComponent

	if transform_comp and velocity_comp:
		var knockback_dir := from_position.direction_to(transform_comp.position)
		knockback_dir.y = 0.2  # Slight upward angle
		velocity_comp.apply_impulse(knockback_dir.normalized() * force)


## Set projectile factory function
func set_projectile_factory(factory: Callable) -> void:
	projectile_factory = factory
