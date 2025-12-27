## PhysicsSystem - Sets up and manages physics bodies for entities
## Handles CharacterBody3D creation and collision management
class_name PhysicsSystem
extends System

## Priority runs early
var priority: int = -20

## Parent node for physics bodies
var physics_parent: Node3D = null


func get_system_name() -> String:
	return "PhysicsSystem"


func get_required_components() -> Array[String]:
	return ["Transform", "Collider"]


func get_optional_components() -> Array[String]:
	return ["Velocity"]


func _on_added() -> void:
	if world and not physics_parent:
		physics_parent = Node3D.new()
		physics_parent.name = "EntityPhysics"
		world.add_child(physics_parent)


func _on_removed() -> void:
	if physics_parent and is_instance_valid(physics_parent):
		physics_parent.queue_free()


func _on_entity_added(entity: Entity) -> void:
	_setup_physics_body(entity)


func _on_entity_removed(entity: Entity) -> void:
	_cleanup_physics_body(entity)


func physics_process_entity(entity: Entity, _delta: float) -> void:
	var transform_comp := entity.get_component("Transform") as TransformComponent
	var collider_comp := entity.get_component("Collider") as ColliderComponent

	if not transform_comp or not collider_comp:
		return

	# Sync CharacterBody3D position if not controlled by MovementSystem
	if collider_comp.character_body and not entity.has_component("Velocity"):
		collider_comp.character_body.global_position = transform_comp.position
		collider_comp.character_body.rotation = transform_comp.rotation


## Setup physics body for entity
func _setup_physics_body(entity: Entity) -> void:
	var transform_comp := entity.get_component("Transform") as TransformComponent
	var collider_comp := entity.get_component("Collider") as ColliderComponent
	var velocity_comp := entity.get_component("Velocity") as VelocityComponent

	if not transform_comp or not collider_comp:
		return

	# Skip if already has a body
	if collider_comp.character_body:
		return

	var parent := physics_parent if physics_parent else world

	# Create CharacterBody3D for entities with velocity
	if velocity_comp:
		var body := CharacterBody3D.new()
		body.name = "Entity_%d_Body" % entity.id
		parent.add_child(body)

		body.global_position = transform_comp.position
		body.rotation = transform_comp.rotation

		# Setup collision
		collider_comp.setup_character_body(body)

		# Link transform to body
		transform_comp.node_3d = body
	elif collider_comp.is_trigger:
		# Create Area3D for triggers
		var area_parent := Node3D.new()
		area_parent.name = "Entity_%d_Trigger" % entity.id
		parent.add_child(area_parent)
		area_parent.global_position = transform_comp.position

		collider_comp.setup_area_trigger(area_parent)
		transform_comp.node_3d = area_parent


## Cleanup physics body for entity
func _cleanup_physics_body(entity: Entity) -> void:
	var collider_comp := entity.get_component("Collider") as ColliderComponent
	if not collider_comp:
		return

	if collider_comp.character_body and is_instance_valid(collider_comp.character_body):
		collider_comp.character_body.queue_free()
		collider_comp.character_body = null

	if collider_comp.area and is_instance_valid(collider_comp.area):
		var area_parent := collider_comp.area.get_parent()
		if area_parent:
			area_parent.queue_free()
		collider_comp.area = null


## Create a CharacterBody3D manually for an entity
func create_character_body(entity: Entity) -> CharacterBody3D:
	var transform_comp := entity.get_component("Transform") as TransformComponent
	var collider_comp := entity.get_component("Collider") as ColliderComponent

	if not collider_comp:
		collider_comp = ColliderComponent.new()
		entity.add_component(collider_comp)

	if collider_comp.character_body:
		return collider_comp.character_body

	var parent := physics_parent if physics_parent else world

	var body := CharacterBody3D.new()
	body.name = "Entity_%d_Body" % entity.id
	parent.add_child(body)

	if transform_comp:
		body.global_position = transform_comp.position
		body.rotation = transform_comp.rotation
		transform_comp.node_3d = body

	collider_comp.setup_character_body(body)
	return body


## Check if entity is on ground
func is_on_ground(entity: Entity) -> bool:
	var collider_comp := entity.get_component("Collider") as ColliderComponent
	if collider_comp:
		return collider_comp.is_on_ground()
	return false


## Get collision normal
func get_ground_normal(entity: Entity) -> Vector3:
	var collider_comp := entity.get_component("Collider") as ColliderComponent
	if collider_comp:
		return collider_comp.get_ground_normal()
	return Vector3.UP


## Set collision layer for entity
func set_collision_layer(entity: Entity, layer: int) -> void:
	var collider_comp := entity.get_component("Collider") as ColliderComponent
	if collider_comp:
		collider_comp.set_layer(layer)


## Set collision mask for entity
func set_collision_mask(entity: Entity, mask: int) -> void:
	var collider_comp := entity.get_component("Collider") as ColliderComponent
	if collider_comp:
		collider_comp.set_mask(mask)


## Enable/disable collision for entity
func set_collision_enabled(entity: Entity, is_enabled: bool) -> void:
	var collider_comp := entity.get_component("Collider") as ColliderComponent
	if collider_comp:
		collider_comp.set_collision_enabled(is_enabled)


## Get overlapping bodies for entity
func get_overlapping_bodies(entity: Entity) -> Array[Node3D]:
	var collider_comp := entity.get_component("Collider") as ColliderComponent
	if collider_comp:
		return collider_comp.get_overlapping_bodies()
	return []
