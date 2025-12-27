## World - The container for all entities and systems
## Manages entity creation, destruction, and system execution
## Acts as the central hub for the ECS architecture
class_name World
extends Node

## Next entity ID to assign
var _next_entity_id: int = 0

## All entities in the world (id -> Entity)
var _entities: Dictionary = {}

## All systems in the world (system_name -> System)
var _systems: Dictionary = {}

## Systems sorted by priority for execution
var _systems_sorted: Array[System] = []

## Entities pending addition (added at end of frame)
var _pending_add: Array[Entity] = []

## Entities pending removal (removed at end of frame)
var _pending_remove: Array[Entity] = []

## Signal emitted when an entity is created
signal entity_created(entity: Entity)

## Signal emitted when an entity is destroyed
signal entity_destroyed(entity: Entity)

## Signal emitted when a system is added
signal system_added(system: System)

## Signal emitted when a system is removed
signal system_removed(system: System)


func _ready() -> void:
	# Process pending entities
	set_process(true)
	set_physics_process(true)


func _process(delta: float) -> void:
	_flush_pending()

	for system in _systems_sorted:
		if system.active:
			system.process(delta)


func _physics_process(delta: float) -> void:
	_flush_pending()

	for system in _systems_sorted:
		if system.active:
			system.physics_process(delta)


## Create a new entity
func create_entity() -> Entity:
	var entity := Entity.new(_next_entity_id, self)
	_next_entity_id += 1
	_pending_add.append(entity)
	return entity


## Create entity and immediately add it (skip pending queue)
func create_entity_immediate() -> Entity:
	var entity := Entity.new(_next_entity_id, self)
	_next_entity_id += 1
	_add_entity(entity)
	return entity


## Remove an entity from the world
func remove_entity(entity: Entity) -> void:
	if not _pending_remove.has(entity):
		_pending_remove.append(entity)


## Remove entity immediately (skip pending queue)
func remove_entity_immediate(entity: Entity) -> void:
	_remove_entity(entity)


## Get an entity by ID
func get_entity(entity_id: int) -> Entity:
	return _entities.get(entity_id)


## Get all entities
func get_all_entities() -> Array[Entity]:
	var result: Array[Entity] = []
	for entity in _entities.values():
		result.append(entity)
	return result


## Get entities with a specific tag
func get_entities_with_tag(tag: String) -> Array[Entity]:
	var result: Array[Entity] = []
	for entity in _entities.values():
		if entity.has_tag(tag):
			result.append(entity)
	return result


## Get entities with specific components
func get_entities_with_components(component_names: Array[String]) -> Array[Entity]:
	var result: Array[Entity] = []
	for entity in _entities.values():
		if entity.has_components(component_names):
			result.append(entity)
	return result


## Get the first entity with a tag
func get_first_entity_with_tag(tag: String) -> Entity:
	for entity in _entities.values():
		if entity.has_tag(tag):
			return entity
	return null


## Add a system to the world
func add_system(system: System) -> World:
	var system_name := system.get_system_name()

	if _systems.has(system_name):
		push_warning("World already has system: %s" % system_name)
		return self

	system.world = self
	_systems[system_name] = system

	# Add to sorted list based on priority
	_systems_sorted.append(system)
	_systems_sorted.sort_custom(func(a: System, b: System): return a.priority < b.priority)

	system._on_added()
	system_added.emit(system)

	# Register existing entities that match
	for entity in _entities.values():
		if system.matches_entity(entity):
			system.add_entity(entity)

	return self


## Remove a system from the world
func remove_system(system_name: String) -> World:
	if not _systems.has(system_name):
		return self

	var system: System = _systems[system_name]
	system._on_removed()
	_systems.erase(system_name)
	_systems_sorted.erase(system)
	system_removed.emit(system)

	return self


## Get a system by name
func get_system(system_name: String) -> System:
	return _systems.get(system_name)


## Get all systems
func get_all_systems() -> Array[System]:
	return _systems_sorted.duplicate()


## Called when a component is added to an entity
func _on_entity_component_added(entity: Entity, _component: Component) -> void:
	# Re-evaluate which systems this entity matches
	for system in _systems_sorted:
		if system.matches_entity(entity):
			system.add_entity(entity)


## Called when a component is removed from an entity
func _on_entity_component_removed(entity: Entity, _component_name: String) -> void:
	# Re-evaluate which systems this entity matches
	for system in _systems_sorted:
		if not system.matches_entity(entity):
			system.remove_entity(entity)


## Flush pending entity additions and removals
func _flush_pending() -> void:
	# Add pending entities
	for entity in _pending_add:
		_add_entity(entity)
	_pending_add.clear()

	# Remove pending entities
	for entity in _pending_remove:
		_remove_entity(entity)
	_pending_remove.clear()


## Internal: Add entity to the world
func _add_entity(entity: Entity) -> void:
	_entities[entity.id] = entity
	entity_created.emit(entity)

	# Register with matching systems
	for system in _systems_sorted:
		if system.matches_entity(entity):
			system.add_entity(entity)


## Internal: Remove entity from the world
func _remove_entity(entity: Entity) -> void:
	if not _entities.has(entity.id):
		return

	# Unregister from all systems
	for system in _systems_sorted:
		system.remove_entity(entity)

	_entities.erase(entity.id)
	entity_destroyed.emit(entity)


## Clear all entities and systems
func clear() -> void:
	# Remove all entities
	for entity in _entities.values():
		entity.destroy()
	_entities.clear()
	_pending_add.clear()
	_pending_remove.clear()

	# Remove all systems
	for system in _systems_sorted:
		system._on_removed()
	_systems.clear()
	_systems_sorted.clear()


## Get entity count
func get_entity_count() -> int:
	return _entities.size()


## Get system count
func get_system_count() -> int:
	return _systems.size()


## Query entities - returns entities matching all given component names
func query(component_names: Array[String]) -> Array[Entity]:
	return get_entities_with_components(component_names)


## Query single - returns first entity matching all given component names
func query_first(component_names: Array[String]) -> Entity:
	for entity in _entities.values():
		if entity.has_components(component_names):
			return entity
	return null
