## System - Base class for all ECS systems
## Systems contain the logic that operates on entities with specific components
## They define which components they require and process matching entities
class_name System
extends RefCounted

## Reference to the world this system belongs to
var world: World = null

## Whether this system is active
var active: bool = true

## Priority for execution order (lower = earlier)
var priority: int = 0

## Cached entities that match this system's component requirements
var _matched_entities: Array[Entity] = []


## Override this to return the system's unique name
func get_system_name() -> String:
	return "System"


## Override this to return required component names
## Only entities with ALL these components will be processed
func get_required_components() -> Array[String]:
	return []


## Override this to return optional component names
## These components are nice to have but not required
func get_optional_components() -> Array[String]:
	return []


## Called when the system is added to the world
func _on_added() -> void:
	pass


## Called when the system is removed from the world
func _on_removed() -> void:
	pass


## Called when an entity is added to this system's cache
func _on_entity_added(entity: Entity) -> void:
	pass


## Called when an entity is removed from this system's cache
func _on_entity_removed(entity: Entity) -> void:
	pass


## Process all matched entities (called every frame)
func process(delta: float) -> void:
	if not active:
		return

	for entity in _matched_entities:
		if entity.active:
			process_entity(entity, delta)


## Process all matched entities (called every physics frame)
func physics_process(delta: float) -> void:
	if not active:
		return

	for entity in _matched_entities:
		if entity.active:
			physics_process_entity(entity, delta)


## Override this to process a single entity each frame
func process_entity(_entity: Entity, _delta: float) -> void:
	pass


## Override this to process a single entity each physics frame
func physics_process_entity(_entity: Entity, _delta: float) -> void:
	pass


## Check if an entity matches this system's requirements
func matches_entity(entity: Entity) -> bool:
	var required := get_required_components()
	return entity.has_components(required)


## Add an entity to the matched cache
func add_entity(entity: Entity) -> void:
	if not _matched_entities.has(entity):
		_matched_entities.append(entity)
		_on_entity_added(entity)


## Remove an entity from the matched cache
func remove_entity(entity: Entity) -> void:
	var idx := _matched_entities.find(entity)
	if idx >= 0:
		_matched_entities.remove_at(idx)
		_on_entity_removed(entity)


## Get all matched entities
func get_entities() -> Array[Entity]:
	return _matched_entities


## Get count of matched entities
func get_entity_count() -> int:
	return _matched_entities.size()


## Query entities with a specific tag
func get_entities_with_tag(tag: String) -> Array[Entity]:
	var result: Array[Entity] = []
	for entity in _matched_entities:
		if entity.has_tag(tag):
			result.append(entity)
	return result
