## ECSManager - Autoload singleton for managing the ECS World
## Provides integration with existing game systems and convenient API
extends Node

## The ECS World instance
var world: World = null

## Entity factory for creating entities
var factory: EntityFactory = null

## Model registry for model paths
var model_registry: ModelRegistry = null

## Reference to player entity
var player_entity: Entity = null

## Active zombie entities
var zombie_entities: Array[Entity] = []

## Systems references for easy access
var movement_system: MovementSystem = null
var health_system: HealthSystem = null
var ai_system: AISystem = null
var render_system: RenderSystem = null
var combat_system: CombatSystem = null
var physics_system: PhysicsSystem = null

## Signal when ECS is initialized
signal ecs_initialized()

## Signal when player entity is created
signal player_created(entity: Entity)

## Signal when zombie entity is created
signal zombie_created(entity: Entity)

## Signal when entity is destroyed
signal entity_destroyed(entity: Entity)


func _ready() -> void:
	initialize()


## Initialize the ECS system
func initialize() -> void:
	if world:
		return

	# Create world
	world = World.new()
	world.name = "ECSWorld"
	add_child(world)

	# Create factory
	factory = EntityFactory.new(world)
	model_registry = factory.model_registry

	# Auto-discover character models
	model_registry.auto_discover_character_models()

	# Create and add systems (order matters!)
	_create_systems()

	# Connect world signals
	world.entity_destroyed.connect(_on_entity_destroyed)

	ecs_initialized.emit()
	print("[ECS] Entity Component System initialized")


## Create and add all systems
func _create_systems() -> void:
	# Physics system (highest priority)
	physics_system = PhysicsSystem.new()
	physics_system.priority = -20
	world.add_system(physics_system)

	# AI system
	ai_system = AISystem.new()
	ai_system.priority = -10
	world.add_system(ai_system)

	# Combat system
	combat_system = CombatSystem.new()
	combat_system.priority = -5
	world.add_system(combat_system)
	combat_system.set_projectile_factory(_create_projectile)

	# Movement system
	movement_system = MovementSystem.new()
	movement_system.priority = 0
	world.add_system(movement_system)

	# Health system
	health_system = HealthSystem.new()
	health_system.priority = 10
	world.add_system(health_system)
	health_system.entity_died.connect(_on_entity_died)

	# Render system (lowest priority)
	render_system = RenderSystem.new()
	render_system.priority = 50
	world.add_system(render_system)


## Create player entity
func create_player(position: Vector3, config: Dictionary = {}) -> Entity:
	if player_entity:
		push_warning("[ECS] Player entity already exists")
		return player_entity

	player_entity = factory.create_player(position, config)
	player_created.emit(player_entity)

	print("[ECS] Player entity created (ID: %d)" % player_entity.id)
	return player_entity


## Create zombie entity
func create_zombie(position: Vector3, zombie_type: String = "shambler",
		config: Dictionary = {}) -> Entity:

	var entity := factory.create_zombie(position, zombie_type, config)
	zombie_entities.append(entity)
	zombie_created.emit(entity)

	print("[ECS] Zombie '%s' created (ID: %d)" % [zombie_type, entity.id])
	return entity


## Create projectile entity
func _create_projectile(config: Dictionary) -> Entity:
	var origin: Vector3 = config.get("origin", Vector3.ZERO)
	var direction: Vector3 = config.get("direction", Vector3.FORWARD)
	return factory.create_projectile(origin, direction, config)


## Spawn zombie at a spawn point
func spawn_zombie_at_point(spawn_point: Node3D, zombie_type: String = "shambler",
		config: Dictionary = {}) -> Entity:

	var position := spawn_point.global_position if spawn_point else Vector3.ZERO
	return create_zombie(position, zombie_type, config)


## Spawn multiple zombies
func spawn_zombies(count: int, spawn_points: Array[Node3D], zombie_type: String = "shambler",
		config: Dictionary = {}) -> Array[Entity]:

	var spawned: Array[Entity] = []

	for i in range(count):
		var spawn_point: Node3D = null
		if not spawn_points.is_empty():
			spawn_point = spawn_points[i % spawn_points.size()]

		var position := spawn_point.global_position if spawn_point else Vector3(
			randf_range(-10, 10),
			0,
			randf_range(-10, 10)
		)

		var entity := create_zombie(position, zombie_type, config)
		spawned.append(entity)

	return spawned


## Get player entity
func get_player() -> Entity:
	return player_entity


## Get all zombie entities
func get_zombies() -> Array[Entity]:
	return zombie_entities


## Get zombie count
func get_zombie_count() -> int:
	return zombie_entities.size()


## Get alive zombie count
func get_alive_zombie_count() -> int:
	var count := 0
	for zombie in zombie_entities:
		var health := zombie.get_component("Health") as HealthComponent
		if health and not health.is_dead:
			count += 1
	return count


## Kill all zombies
func kill_all_zombies() -> void:
	for zombie in zombie_entities:
		var health := zombie.get_component("Health") as HealthComponent
		if health:
			health.kill()


## Remove all zombie entities
func clear_zombies() -> void:
	for zombie in zombie_entities:
		zombie.destroy()
	zombie_entities.clear()


## Get entity by ID
func get_entity(id: int) -> Entity:
	if world:
		return world.get_entity(id)
	return null


## Get entities with tag
func get_entities_with_tag(tag: String) -> Array[Entity]:
	if world:
		return world.get_entities_with_tag(tag)
	return []


## Deal damage to entity
func deal_damage(target: Entity, damage: float, source: Entity = null) -> float:
	if health_system:
		return health_system.deal_damage(target, damage, source)
	return 0.0


## Heal entity
func heal_entity(target: Entity, amount: float) -> float:
	if health_system:
		return health_system.heal_entity(target, amount)
	return 0.0


## Apply status effect to entity
func apply_status_effect(target: Entity, effect_name: String, duration: float,
		value: float = 0.0) -> void:

	var status := target.get_component("StatusEffect") as StatusEffectComponent
	if status:
		var effect_type := "dot" if effect_name in ["poison", "bleed", "burn"] else "debuff"
		status.apply_effect(effect_name, effect_type, duration, value)


## Set player weapon from ItemData
func set_player_weapon(item_data: Resource) -> void:
	if not player_entity:
		return

	var weapon := player_entity.get_component("Weapon") as WeaponComponent
	if weapon:
		weapon.setup_from_item_data(item_data)


## Get player health percentage
func get_player_health_percent() -> float:
	if not player_entity:
		return 0.0

	var health := player_entity.get_component("Health") as HealthComponent
	if health:
		return health.get_health_percent()
	return 0.0


## Get player position
func get_player_position() -> Vector3:
	if not player_entity:
		return Vector3.ZERO

	var transform := player_entity.get_component("Transform") as TransformComponent
	if transform:
		return transform.position
	return Vector3.ZERO


## Handle entity death
func _on_entity_died(entity: Entity, _killer: Entity) -> void:
	if entity.has_tag("zombie"):
		# Zombie died - could trigger loot drop, etc.
		pass


## Handle entity destruction
func _on_entity_destroyed(entity: Entity) -> void:
	if entity == player_entity:
		player_entity = null

	if entity.has_tag("zombie"):
		zombie_entities.erase(entity)

	entity_destroyed.emit(entity)


## Cleanup
func cleanup() -> void:
	if player_entity:
		player_entity.destroy()
		player_entity = null

	for zombie in zombie_entities:
		zombie.destroy()
	zombie_entities.clear()

	if world:
		world.clear()


func _exit_tree() -> void:
	cleanup()
