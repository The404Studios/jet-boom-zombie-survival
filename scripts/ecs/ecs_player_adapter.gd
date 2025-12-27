## ECSPlayerAdapter - Adapts ECS player entity to work with existing player scene
## Bridges the gap between ECS and the existing player controller
extends Node

## Reference to ECS Manager
var ecs_manager: Node = null

## The ECS player entity
var player_entity: Entity = null

## The existing player CharacterBody3D (from scene)
var player_body: CharacterBody3D = null

## The existing Camera3D
var player_camera: Camera3D = null

## Whether to use ECS for movement (vs existing script)
@export var use_ecs_movement: bool = true

## Whether to use ECS for combat
@export var use_ecs_combat: bool = true


func _ready() -> void:
	# Get references
	player_body = get_parent() as CharacterBody3D
	if not player_body:
		push_error("[ECSPlayerAdapter] Must be child of CharacterBody3D")
		return

	# Find camera
	player_camera = _find_camera(player_body)

	# Wait for ECS to initialize
	await get_tree().process_frame
	_setup_ecs_player()


## Find camera in player hierarchy
func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node

	for child in node.get_children():
		var cam := _find_camera(child)
		if cam:
			return cam

	return null


## Setup ECS player entity
func _setup_ecs_player() -> void:
	ecs_manager = get_node_or_null("/root/ECSManager")
	if not ecs_manager:
		push_warning("[ECSPlayerAdapter] ECSManager not found, using legacy player")
		return

	# Create ECS player entity at current position
	var config := {
		"walk_speed": 5.0,
		"sprint_speed": 8.0,
		"jump_velocity": 6.0,
		"max_health": 100.0,
		"max_stamina": 100.0,
	}

	player_entity = ecs_manager.create_player(player_body.global_position, config)

	if player_entity:
		_link_entity_to_scene()
		print("[ECSPlayerAdapter] Player entity linked to scene")


## Link ECS entity components to existing scene nodes
func _link_entity_to_scene() -> void:
	if not player_entity:
		return

	# Link transform to CharacterBody3D
	var transform := player_entity.get_component("Transform") as TransformComponent
	if transform:
		transform.node_3d = player_body

	# Link collider to CharacterBody3D
	var collider := player_entity.get_component("Collider") as ColliderComponent
	if collider:
		collider.character_body = player_body
		# Don't create new collision shape, use existing
		collider.collision_shape = _find_collision_shape(player_body)

	# Setup player controller with camera
	var controller := player_entity.get_component("PlayerController") as PlayerControllerComponent
	if controller and player_camera:
		controller.setup_camera(player_camera, _find_weapon_holder())
		controller.setup_interact_ray(_find_interact_ray())


## Find collision shape in player
func _find_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node

	for child in node.get_children():
		var shape := _find_collision_shape(child)
		if shape:
			return shape

	return null


## Find weapon holder node
func _find_weapon_holder() -> Node3D:
	var holder := player_body.find_child("WeaponHolder", true, false)
	return holder as Node3D


## Find interact ray
func _find_interact_ray() -> RayCast3D:
	var ray := player_body.find_child("InteractRay", true, false)
	return ray as RayCast3D


func _unhandled_input(event: InputEvent) -> void:
	if not player_entity:
		return

	# Handle mouse motion for camera
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var controller := player_entity.get_component("PlayerController") as PlayerControllerComponent
		if controller:
			controller.handle_mouse_motion(event)


## Get ECS player entity
func get_entity() -> Entity:
	return player_entity


## Get player controller component
func get_controller() -> PlayerControllerComponent:
	if player_entity:
		return player_entity.get_component("PlayerController") as PlayerControllerComponent
	return null


## Get player health component
func get_health() -> HealthComponent:
	if player_entity:
		return player_entity.get_component("Health") as HealthComponent
	return null


## Get player weapon component
func get_weapon() -> WeaponComponent:
	if player_entity:
		return player_entity.get_component("Weapon") as WeaponComponent
	return null


## Equip weapon from ItemData
func equip_weapon(item_data: Resource) -> void:
	var weapon := get_weapon()
	if weapon:
		weapon.setup_from_item_data(item_data)


## Take damage (interface for existing systems)
func take_damage(amount: float, source: Node = null) -> void:
	var health := get_health()
	if health:
		# Convert Node source to Entity if possible
		var source_entity: Entity = null
		if ecs_manager and source:
			# Try to find entity for this node
			for entity in ecs_manager.get_entities_with_tag("zombie"):
				var transform := entity.get_component("Transform") as TransformComponent
				if transform and transform.node_3d == source:
					source_entity = entity
					break

		health.take_damage(amount, source_entity)


## Heal player (interface for existing systems)
func heal(amount: float) -> void:
	var health := get_health()
	if health:
		health.heal(amount)


## Get current health
func get_current_health() -> float:
	var health := get_health()
	if health:
		return health.current
	return 0.0


## Get max health
func get_max_health() -> float:
	var health := get_health()
	if health:
		return health.maximum
	return 0.0


## Check if player is dead
func is_dead() -> bool:
	var health := get_health()
	if health:
		return health.is_dead
	return false
