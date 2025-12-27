## ProjectileControllerComponent - Controller for projectile entities
## Handles projectile movement, lifetime, and hit detection
class_name ProjectileControllerComponent
extends ControllerComponent

## Projectile type
enum ProjectileType {
	BULLET,
	ROCKET,
	GRENADE,
	ARROW,
	ACID,
	FIREBALL,
	CUSTOM
}

## Type of projectile
var projectile_type: ProjectileType = ProjectileType.BULLET

## Movement speed
var speed: float = 50.0

## Damage on hit
var damage: float = 10.0

## Damage type
var damage_type: String = "physical"

## Explosion radius (0 = no explosion)
var explosion_radius: float = 0.0

## Explosion damage
var explosion_damage: float = 0.0

## Lifetime in seconds
var lifetime: float = 5.0

## Time alive
var time_alive: float = 0.0

## Whether projectile has hit something
var has_hit: bool = false

## Source entity (who fired this)
var source_entity: Entity = null

## Source entity ID (for serialization)
var source_entity_id: int = -1

## Gravity effect (0 = no gravity, 1 = full gravity)
var gravity_scale: float = 0.0

## Whether to pierce through targets
var piercing: bool = false

## Number of targets pierced
var pierce_count: int = 0

## Maximum pierce targets
var max_pierce: int = 1

## Homing settings
var is_homing: bool = false
var homing_strength: float = 5.0
var homing_target: Entity = null

## Trail effect settings
var has_trail: bool = false
var trail_color: Color = Color.WHITE

## On-hit status effect
var apply_status_effect: String = ""
var status_effect_duration: float = 0.0
var status_effect_value: float = 0.0

## Collision mask for hit detection
var hit_mask: int = 6  # Zombies layer by default

## Tags to ignore (won't hit entities with these tags)
var ignore_tags: Array[String] = []

## Direction of travel
var direction: Vector3 = Vector3.FORWARD

## Signal when hit something
signal hit_target(target: Node3D, position: Vector3)

## Signal when exploded
signal exploded(position: Vector3)

## Signal when lifetime expired
signal expired()


func get_component_name() -> String:
	return "ProjectileController"


func _init() -> void:
	controller_type = ControllerType.PROJECTILE


## Initialize projectile
func setup(fire_direction: Vector3, fire_speed: float, fire_damage: float, source: Entity = null) -> void:
	direction = fire_direction.normalized()
	speed = fire_speed
	damage = fire_damage
	source_entity = source
	source_entity_id = source.id if source else -1
	look_direction = direction
	has_hit = false
	time_alive = 0.0


## Update projectile
func _update_controller(delta: float) -> void:
	if not controller_active or has_hit:
		return

	time_alive += delta

	# Check lifetime
	if time_alive >= lifetime:
		_expire()
		return

	# Homing behavior
	if is_homing and homing_target and is_instance_valid(homing_target):
		_update_homing(delta)

	# Set movement direction
	input_direction = direction

	# Apply gravity
	if gravity_scale > 0:
		direction.y -= 9.8 * gravity_scale * delta
		direction = direction.normalized()


## Update homing behavior
func _update_homing(delta: float) -> void:
	if not homing_target:
		return

	var target_transform := homing_target.get_component("Transform") as TransformComponent
	if not target_transform:
		return

	var transform_comp := entity.get_component("Transform") as TransformComponent
	if not transform_comp:
		return

	var to_target := transform_comp.position.direction_to(target_transform.position)
	direction = direction.lerp(to_target, homing_strength * delta).normalized()
	look_direction = direction


## Handle hitting a target
func on_hit(target: Node3D, hit_position: Vector3) -> void:
	if has_hit and not piercing:
		return

	# Check if should ignore this target
	if target is Entity:
		var target_entity := target as Entity
		for tag in ignore_tags:
			if target_entity.has_tag(tag):
				return

		# Don't hit source
		if source_entity and target_entity == source_entity:
			return

	hit_target.emit(target, hit_position)

	# Deal damage
	_apply_damage(target)

	# Apply status effect
	if apply_status_effect != "":
		_apply_status_effect(target)

	# Handle piercing
	if piercing:
		pierce_count += 1
		if pierce_count >= max_pierce:
			has_hit = true
			_on_final_hit(hit_position)
	else:
		has_hit = true
		_on_final_hit(hit_position)


## Apply damage to target
func _apply_damage(target: Node3D) -> void:
	# Try to get health component from entity
	if target is Entity:
		var health_comp := (target as Entity).get_component("Health") as HealthComponent
		if health_comp:
			health_comp.take_damage(damage, source_entity)
			return

	# Try to find health component on node
	if target.has_method("take_damage"):
		target.take_damage(damage)
	elif target.has_node("HealthComponent"):
		var health := target.get_node("HealthComponent")
		if health.has_method("take_damage"):
			health.take_damage(damage)


## Apply status effect to target
func _apply_status_effect(target: Node3D) -> void:
	if apply_status_effect.is_empty():
		return

	if target is Entity:
		var status_comp := (target as Entity).get_component("StatusEffect") as StatusEffectComponent
		if status_comp:
			status_comp.apply_effect(
				apply_status_effect,
				"dot" if apply_status_effect in ["poison", "bleed", "burn"] else "debuff",
				status_effect_duration,
				status_effect_value,
				source_entity_id
			)


## Handle final hit (no more piercing)
func _on_final_hit(position: Vector3) -> void:
	controller_active = false

	# Explode if has explosion radius
	if explosion_radius > 0:
		_explode(position)

	# Destroy entity
	if entity:
		entity.destroy()


## Explode at position
func _explode(position: Vector3) -> void:
	exploded.emit(position)

	if not entity or not entity.world:
		return

	# Find entities in explosion radius
	var all_entities := entity.world.get_all_entities()
	for target_entity in all_entities:
		if target_entity == entity or target_entity == source_entity:
			continue

		var transform_comp := target_entity.get_component("Transform") as TransformComponent
		if not transform_comp:
			continue

		var distance := position.distance_to(transform_comp.position)
		if distance <= explosion_radius:
			# Calculate falloff damage
			var falloff := 1.0 - (distance / explosion_radius)
			var final_damage := explosion_damage * falloff

			var health_comp := target_entity.get_component("Health") as HealthComponent
			if health_comp:
				health_comp.take_damage(final_damage, source_entity)


## Expire the projectile (lifetime ended)
func _expire() -> void:
	expired.emit()
	controller_active = false

	# Explode if has explosion (like grenades)
	if explosion_radius > 0:
		var transform_comp := entity.get_component("Transform") as TransformComponent
		if transform_comp:
			_explode(transform_comp.position)

	# Destroy entity
	if entity:
		entity.destroy()


## Set homing target
func set_homing_target(target: Entity) -> void:
	homing_target = target
	is_homing = target != null


## Get remaining lifetime
func get_remaining_lifetime() -> float:
	return maxf(lifetime - time_alive, 0.0)


## Check if projectile is active
func is_active() -> bool:
	return controller_active and not has_hit and time_alive < lifetime


func serialize() -> Dictionary:
	var data := super.serialize()
	data["projectile_type"] = projectile_type
	data["speed"] = speed
	data["damage"] = damage
	data["damage_type"] = damage_type
	data["explosion_radius"] = explosion_radius
	data["explosion_damage"] = explosion_damage
	data["lifetime"] = lifetime
	data["time_alive"] = time_alive
	data["gravity_scale"] = gravity_scale
	data["piercing"] = piercing
	data["source_entity_id"] = source_entity_id
	data["direction"] = {"x": direction.x, "y": direction.y, "z": direction.z}
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	projectile_type = data.get("projectile_type", ProjectileType.BULLET)
	speed = data.get("speed", 50.0)
	damage = data.get("damage", 10.0)
	damage_type = data.get("damage_type", "physical")
	explosion_radius = data.get("explosion_radius", 0.0)
	explosion_damage = data.get("explosion_damage", 0.0)
	lifetime = data.get("lifetime", 5.0)
	time_alive = data.get("time_alive", 0.0)
	gravity_scale = data.get("gravity_scale", 0.0)
	piercing = data.get("piercing", false)
	source_entity_id = data.get("source_entity_id", -1)
	if data.has("direction"):
		var d: Dictionary = data["direction"]
		direction = Vector3(d.get("x", 0), d.get("y", 0), d.get("z", -1))
