## ECSZombieAdapter - Adapts ECS zombie entity to work with existing zombie scenes
## Bridges the gap between ECS and the existing zombie controller
extends Node

## Reference to ECS Manager
var ecs_manager: Node = null

## The ECS zombie entity
var zombie_entity: Entity = null

## The existing zombie CharacterBody3D (from scene)
var zombie_body: CharacterBody3D = null

## Zombie type from scene
@export var zombie_type: String = "shambler"

## Override stats (optional)
@export var health_override: float = -1.0
@export var damage_override: float = -1.0
@export var speed_override: float = -1.0

## Whether entity is created
var is_initialized: bool = false


func _ready() -> void:
	# Get references
	zombie_body = get_parent() as CharacterBody3D
	if not zombie_body:
		push_error("[ECSZombieAdapter] Must be child of CharacterBody3D")
		return

	# Wait for ECS to initialize
	await get_tree().process_frame
	_setup_ecs_zombie()


## Setup ECS zombie entity
func _setup_ecs_zombie() -> void:
	ecs_manager = get_node_or_null("/root/ECSManager")
	if not ecs_manager:
		push_warning("[ECSZombieAdapter] ECSManager not found, using legacy zombie")
		return

	# Create config from overrides
	var config := {}

	if health_override > 0:
		config["health"] = health_override
	if damage_override > 0:
		config["damage"] = damage_override
	if speed_override > 0:
		config["move_speed"] = speed_override

	# Create ECS zombie entity at current position
	zombie_entity = ecs_manager.create_zombie(zombie_body.global_position, zombie_type, config)

	if zombie_entity:
		_link_entity_to_scene()
		is_initialized = true
		print("[ECSZombieAdapter] Zombie entity linked to scene (type: %s)" % zombie_type)


## Link ECS entity components to existing scene nodes
func _link_entity_to_scene() -> void:
	if not zombie_entity:
		return

	# Link transform to CharacterBody3D
	var transform := zombie_entity.get_component("Transform") as TransformComponent
	if transform:
		transform.node_3d = zombie_body

	# Link collider to CharacterBody3D
	var collider := zombie_entity.get_component("Collider") as ColliderComponent
	if collider:
		collider.character_body = zombie_body
		collider.collision_shape = _find_collision_shape(zombie_body)

	# Setup navigation agent
	var navigation := zombie_entity.get_component("Navigation") as NavigationComponent
	if navigation:
		var existing_nav := _find_nav_agent(zombie_body)
		if existing_nav:
			navigation.nav_agent = existing_nav
		else:
			navigation.setup_nav_agent(zombie_body)

	# Link model to existing mesh
	var model := zombie_entity.get_component("Model") as ModelComponent
	if model:
		var mesh := _find_mesh_instance(zombie_body)
		if mesh:
			model.model_instance = mesh.get_parent() if mesh.get_parent() is Node3D else mesh

	# Set spawn position for wandering
	var controller := zombie_entity.get_component("ZombieController") as ZombieControllerComponent
	if controller:
		controller.spawn_position = zombie_body.global_position

	# Connect death signal
	var health := zombie_entity.get_component("Health") as HealthComponent
	if health:
		health.died.connect(_on_zombie_died)


## Find collision shape in zombie
func _find_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node

	for child in node.get_children():
		var shape := _find_collision_shape(child)
		if shape:
			return shape

	return null


## Find navigation agent
func _find_nav_agent(node: Node) -> NavigationAgent3D:
	if node is NavigationAgent3D:
		return node

	for child in node.get_children():
		var agent := _find_nav_agent(child)
		if agent:
			return agent

	return null


## Find mesh instance
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node

	for child in node.get_children():
		var mesh := _find_mesh_instance(child)
		if mesh:
			return mesh

	return null


## Handle zombie death
func _on_zombie_died(_killer: Entity) -> void:
	# Trigger death animation on scene
	var anim_player := zombie_body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player and anim_player.has_animation("death"):
		anim_player.play("death")

	# Disable collision
	var collider := zombie_entity.get_component("Collider") as ColliderComponent
	if collider:
		collider.set_collision_enabled(false)

	# Queue free after delay
	await get_tree().create_timer(3.0).timeout
	zombie_body.queue_free()


## Get ECS zombie entity
func get_entity() -> Entity:
	return zombie_entity


## Get zombie controller component
func get_controller() -> ZombieControllerComponent:
	if zombie_entity:
		return zombie_entity.get_component("ZombieController") as ZombieControllerComponent
	return null


## Get zombie health component
func get_health() -> HealthComponent:
	if zombie_entity:
		return zombie_entity.get_component("Health") as HealthComponent
	return null


## Take damage (interface for existing systems)
func take_damage(amount: float, source: Node = null) -> void:
	var health := get_health()
	if health:
		var source_entity: Entity = null

		# Try to find player entity as source
		if ecs_manager and source:
			source_entity = ecs_manager.get_player()

		health.take_damage(amount, source_entity)


## Check if zombie is dead
func is_dead() -> bool:
	var health := get_health()
	if health:
		return health.is_dead
	return false


## Set target (for compatibility with existing scripts)
func set_target(target: Node3D) -> void:
	var controller := get_controller()
	var navigation := zombie_entity.get_component("Navigation") as NavigationComponent

	if controller and target:
		# Find entity for target node
		if ecs_manager:
			var player := ecs_manager.get_player()
			if player:
				var player_transform := player.get_component("Transform") as TransformComponent
				if player_transform and player_transform.node_3d == target:
					controller.target_entity = player
					if navigation:
						navigation.set_target_entity(player)
					return

		# Fallback to position target
		controller.target_position = target.global_position
		if navigation:
			navigation.set_target(target.global_position)


## Stun the zombie
func stun(duration: float) -> void:
	var controller := get_controller()
	if controller:
		controller.apply_stun(duration)
