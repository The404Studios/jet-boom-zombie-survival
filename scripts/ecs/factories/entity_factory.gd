## EntityFactory - Factory for creating common entity types
## Provides convenience methods for spawning players, zombies, projectiles, etc.
class_name EntityFactory
extends RefCounted

## Reference to the world
var world: World = null

## Model registry for model paths
var model_registry: ModelRegistry = null


func _init(ecs_world: World) -> void:
	world = ecs_world
	model_registry = ModelRegistry.new()


## Create a player entity
func create_player(position: Vector3, config: Dictionary = {}) -> Entity:
	var entity := world.create_entity_immediate()
	entity.add_tag("player")

	# Transform
	var transform := TransformComponent.new()
	transform.position = position
	entity.add_component(transform)

	# Velocity
	var velocity := VelocityComponent.new()
	velocity.max_speed = config.get("walk_speed", 5.0)
	velocity.use_gravity = true
	velocity.gravity_scale = 1.0
	entity.add_component(velocity)

	# Health
	var health := HealthComponent.new()
	health.maximum = config.get("max_health", 100.0)
	health.current = health.maximum
	entity.add_component(health)

	# Collider
	var collider := ColliderComponent.new()
	collider.shape_type = ColliderComponent.ShapeType.CAPSULE
	collider.capsule_radius = 0.4
	collider.capsule_height = 1.8
	collider.collision_layer = 2  # Player layer
	collider.collision_mask = 1 | 4 | 8  # Environment, Zombies, Items
	entity.add_component(collider)

	# Model
	var model := ModelComponent.new()
	var model_path := config.get("model_path", model_registry.get_player_model())
	if model_path != "":
		model.load_model(model_path)
	model.model_scale = config.get("model_scale", Vector3.ONE)
	entity.add_component(model)

	# Player Controller
	var controller := PlayerControllerComponent.new()
	controller.walk_speed = config.get("walk_speed", 5.0)
	controller.sprint_speed = config.get("sprint_speed", 8.0)
	controller.jump_velocity = config.get("jump_velocity", 6.0)
	controller.mouse_sensitivity = config.get("mouse_sensitivity", 0.003)
	controller.max_stamina = config.get("max_stamina", 100.0)
	controller.stamina = controller.max_stamina
	entity.add_component(controller)

	# Weapon (default fists)
	var weapon := WeaponComponent.new()
	weapon.weapon_type = WeaponComponent.WeaponType.MELEE
	weapon.weapon_name = "Fists"
	weapon.damage = 10.0
	weapon.fire_rate = 2.0
	weapon.weapon_range = 2.0
	entity.add_component(weapon)

	# Status Effects
	var status := StatusEffectComponent.new()
	entity.add_component(status)

	return entity


## Create a zombie entity
func create_zombie(position: Vector3, zombie_type: String = "shambler",
		config: Dictionary = {}) -> Entity:

	var entity := world.create_entity_immediate()
	entity.add_tag("zombie")
	entity.add_tag(zombie_type)

	# Get zombie class defaults
	var class_defaults := _get_zombie_class_defaults(zombie_type)

	# Transform
	var transform := TransformComponent.new()
	transform.position = position
	entity.add_component(transform)

	# Velocity
	var velocity := VelocityComponent.new()
	velocity.max_speed = config.get("move_speed", class_defaults.get("move_speed", 3.0))
	velocity.use_gravity = true
	velocity.acceleration = 30.0
	entity.add_component(velocity)

	# Health
	var health := HealthComponent.new()
	health.maximum = config.get("health", class_defaults.get("health", 100.0))
	health.current = health.maximum
	health.armor = config.get("armor", class_defaults.get("armor", 0.0))
	entity.add_component(health)

	# Collider
	var collider := ColliderComponent.new()
	collider.shape_type = ColliderComponent.ShapeType.CAPSULE
	collider.capsule_radius = config.get("radius", 0.4)
	collider.capsule_height = config.get("height", 1.8)
	collider.collision_layer = 4  # Zombie layer
	collider.collision_mask = 1 | 2 | 4 | 16  # Environment, Player, Zombies, Barricades
	entity.add_component(collider)

	# Model
	var model := ModelComponent.new()
	var model_path := config.get("model_path", model_registry.get_zombie_model(zombie_type))
	if model_path != "":
		model.load_model(model_path)
	model.tint_color = config.get("tint_color", class_defaults.get("tint_color", Color.WHITE))
	model.model_scale = config.get("model_scale", class_defaults.get("model_scale", Vector3.ONE))
	entity.add_component(model)

	# Navigation
	var navigation := NavigationComponent.new()
	navigation.detection_range = config.get("detection_range", class_defaults.get("detection_range", 20.0))
	navigation.attack_range = config.get("attack_range", class_defaults.get("attack_range", 2.0))
	navigation.avoidance_enabled = true
	entity.add_component(navigation)

	# Zombie Controller
	var controller := ZombieControllerComponent.new()
	controller.move_speed = velocity.max_speed
	controller.attack_damage = config.get("damage", class_defaults.get("damage", 10.0))
	controller.attack_range = navigation.attack_range
	controller.attack_cooldown = config.get("attack_cooldown", class_defaults.get("attack_cooldown", 1.0))
	controller.detection_range = navigation.detection_range
	controller.spawn_position = position
	controller.can_break_barricades = config.get("can_break_barricades", class_defaults.get("can_break_barricades", false))
	controller.is_boss = config.get("is_boss", class_defaults.get("is_boss", false))
	controller.rage_threshold = config.get("rage_threshold", 0.3)
	entity.add_component(controller)

	# Status Effects
	var status := StatusEffectComponent.new()
	entity.add_component(status)

	return entity


## Create a projectile entity
func create_projectile(origin: Vector3, direction: Vector3, config: Dictionary = {}) -> Entity:
	var entity := world.create_entity_immediate()
	entity.add_tag("projectile")

	# Transform
	var transform := TransformComponent.new()
	transform.position = origin
	transform.look_at_position(origin + direction)
	entity.add_component(transform)

	# Velocity
	var velocity := VelocityComponent.new()
	velocity.max_speed = config.get("speed", 50.0)
	velocity.linear = direction.normalized() * velocity.max_speed
	velocity.use_gravity = config.get("use_gravity", false)
	velocity.gravity_scale = config.get("gravity_scale", 0.0)
	entity.add_component(velocity)

	# Collider (as trigger)
	var collider := ColliderComponent.new()
	collider.shape_type = ColliderComponent.ShapeType.SPHERE
	collider.sphere_radius = config.get("radius", 0.1)
	collider.collision_layer = 32  # Projectile layer
	collider.collision_mask = config.get("hit_mask", 4)  # Default: zombies
	collider.is_trigger = true
	entity.add_component(collider)

	# Model (optional)
	var model := ModelComponent.new()
	var model_path: String = config.get("model_path", "")
	if model_path != "":
		model.load_model(model_path)
	model.model_scale = config.get("model_scale", Vector3(0.1, 0.1, 0.1))
	entity.add_component(model)

	# Projectile Controller
	var controller := ProjectileControllerComponent.new()
	controller.setup(direction, velocity.max_speed, config.get("damage", 10.0), config.get("source", null))
	controller.lifetime = config.get("lifetime", 5.0)
	controller.explosion_radius = config.get("explosion_radius", 0.0)
	controller.explosion_damage = config.get("explosion_damage", 0.0)
	controller.piercing = config.get("piercing", false)
	controller.is_homing = config.get("homing", false)
	controller.apply_status_effect = config.get("status_effect", "")
	controller.status_effect_duration = config.get("status_effect_duration", 0.0)

	if config.has("ignore_tags"):
		controller.ignore_tags = config["ignore_tags"]
	else:
		controller.ignore_tags = ["player"]  # Default: don't hit player

	entity.add_component(controller)

	return entity


## Create a pickup item entity
func create_pickup(position: Vector3, item_type: String, config: Dictionary = {}) -> Entity:
	var entity := world.create_entity_immediate()
	entity.add_tag("pickup")
	entity.add_tag(item_type)

	# Transform
	var transform := TransformComponent.new()
	transform.position = position
	entity.add_component(transform)

	# Collider (trigger)
	var collider := ColliderComponent.new()
	collider.shape_type = ColliderComponent.ShapeType.SPHERE
	collider.sphere_radius = config.get("radius", 0.5)
	collider.collision_layer = 8  # Item layer
	collider.collision_mask = 2  # Player only
	collider.is_trigger = true
	entity.add_component(collider)

	# Model
	var model := ModelComponent.new()
	var model_path: String = config.get("model_path", model_registry.get_pickup_model(item_type))
	if model_path != "":
		model.load_model(model_path)
	model.model_scale = config.get("model_scale", Vector3.ONE)
	entity.add_component(model)

	return entity


## Create a barricade entity
func create_barricade(position: Vector3, config: Dictionary = {}) -> Entity:
	var entity := world.create_entity_immediate()
	entity.add_tag("barricade")

	# Transform
	var transform := TransformComponent.new()
	transform.position = position
	entity.add_component(transform)

	# Health
	var health := HealthComponent.new()
	health.maximum = config.get("health", 200.0)
	health.current = health.maximum
	entity.add_component(health)

	# Collider
	var collider := ColliderComponent.new()
	collider.shape_type = ColliderComponent.ShapeType.BOX
	collider.box_size = config.get("size", Vector3(2, 2, 0.3))
	collider.collision_layer = 16  # Barricade layer
	collider.collision_mask = 4  # Zombies
	entity.add_component(collider)

	# Model
	var model := ModelComponent.new()
	var model_path: String = config.get("model_path", "")
	if model_path != "":
		model.load_model(model_path)
	entity.add_component(model)

	return entity


## Get zombie class defaults
func _get_zombie_class_defaults(zombie_type: String) -> Dictionary:
	match zombie_type:
		"shambler":
			return {
				"health": 100.0,
				"move_speed": 3.0,
				"damage": 10.0,
				"attack_range": 2.0,
				"attack_cooldown": 1.0,
				"detection_range": 20.0,
				"armor": 0.0,
				"tint_color": Color(0.5, 0.5, 0.5),
				"model_scale": Vector3.ONE,
				"can_break_barricades": false,
				"is_boss": false
			}
		"runner":
			return {
				"health": 60.0,
				"move_speed": 6.0,
				"damage": 8.0,
				"attack_range": 2.0,
				"attack_cooldown": 0.8,
				"detection_range": 25.0,
				"armor": 0.0,
				"tint_color": Color(0.6, 0.3, 0.3),
				"model_scale": Vector3(0.9, 0.9, 0.9),
				"can_break_barricades": false,
				"is_boss": false
			}
		"tank":
			return {
				"health": 300.0,
				"move_speed": 1.5,
				"damage": 25.0,
				"attack_range": 2.5,
				"attack_cooldown": 1.5,
				"detection_range": 15.0,
				"armor": 10.0,
				"tint_color": Color(0.3, 0.25, 0.4),
				"model_scale": Vector3(1.3, 1.3, 1.3),
				"can_break_barricades": true,
				"is_boss": false
			}
		"poison":
			return {
				"health": 80.0,
				"move_speed": 4.0,
				"damage": 5.0,
				"attack_range": 2.0,
				"attack_cooldown": 0.5,
				"detection_range": 20.0,
				"armor": 0.0,
				"tint_color": Color(0.2, 0.6, 0.2),
				"model_scale": Vector3.ONE,
				"can_break_barricades": false,
				"is_boss": false
			}
		"exploder":
			return {
				"health": 50.0,
				"move_speed": 5.0,
				"damage": 50.0,
				"attack_range": 1.0,
				"attack_cooldown": 999.0,  # Only explodes once
				"detection_range": 25.0,
				"armor": 0.0,
				"tint_color": Color(0.8, 0.3, 0.1),
				"model_scale": Vector3(1.1, 1.1, 1.1),
				"can_break_barricades": false,
				"is_boss": false
			}
		"spitter":
			return {
				"health": 70.0,
				"move_speed": 3.5,
				"damage": 15.0,
				"attack_range": 10.0,
				"attack_cooldown": 2.0,
				"detection_range": 20.0,
				"armor": 0.0,
				"tint_color": Color(0.5, 0.7, 0.2),
				"model_scale": Vector3.ONE,
				"can_break_barricades": false,
				"is_boss": false
			}
		"boss_behemoth":
			return {
				"health": 1000.0,
				"move_speed": 2.0,
				"damage": 50.0,
				"attack_range": 3.0,
				"attack_cooldown": 2.0,
				"detection_range": 30.0,
				"armor": 20.0,
				"tint_color": Color(0.4, 0.2, 0.2),
				"model_scale": Vector3(2.0, 2.0, 2.0),
				"can_break_barricades": true,
				"is_boss": true
			}
		_:
			return {
				"health": 100.0,
				"move_speed": 3.0,
				"damage": 10.0,
				"attack_range": 2.0,
				"attack_cooldown": 1.0,
				"detection_range": 20.0,
				"armor": 0.0,
				"tint_color": Color.WHITE,
				"model_scale": Vector3.ONE,
				"can_break_barricades": false,
				"is_boss": false
			}
