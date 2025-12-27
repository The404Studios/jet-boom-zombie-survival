## Entity - The fundamental building block of the ECS
## An entity is just a unique identifier with associated components
## Entities are lightweight containers that hold references to components
class_name Entity
extends RefCounted

## Unique identifier for this entity
var id: int = -1

## Reference to the world this entity belongs to
var world: World = null

## Whether this entity is active (processed by systems)
var active: bool = true

## Tags for quick filtering (e.g., "player", "zombie", "projectile")
var tags: Array[String] = []

## Components attached to this entity (component_name -> Component)
var _components: Dictionary = {}

## Signal emitted when a component is added
signal component_added(component: Component)

## Signal emitted when a component is removed
signal component_removed(component_name: String)

## Signal emitted when entity is destroyed
signal destroyed()


func _init(entity_id: int, entity_world: World = null) -> void:
	id = entity_id
	world = entity_world


## Add a component to this entity
func add_component(component: Component) -> Entity:
	var component_name := component.get_component_name()

	if _components.has(component_name):
		push_warning("Entity %d already has component: %s" % [id, component_name])
		return self

	component.entity = self
	_components[component_name] = component
	component._on_added()
	component_added.emit(component)

	# Notify world for system registration
	if world:
		world._on_entity_component_added(self, component)

	return self


## Remove a component from this entity
func remove_component(component_name: String) -> Entity:
	if not _components.has(component_name):
		return self

	var component: Component = _components[component_name]
	component._on_removed()
	_components.erase(component_name)
	component_removed.emit(component_name)

	# Notify world for system deregistration
	if world:
		world._on_entity_component_removed(self, component_name)

	return self


## Get a component by name
func get_component(component_name: String) -> Component:
	return _components.get(component_name)


## Check if entity has a component
func has_component(component_name: String) -> bool:
	return _components.has(component_name)


## Check if entity has all specified components
func has_components(component_names: Array[String]) -> bool:
	for name in component_names:
		if not _components.has(name):
			return false
	return true


## Get all components
func get_all_components() -> Array[Component]:
	var result: Array[Component] = []
	for comp in _components.values():
		result.append(comp)
	return result


## Add a tag to this entity
func add_tag(tag: String) -> Entity:
	if not tags.has(tag):
		tags.append(tag)
	return self


## Remove a tag from this entity
func remove_tag(tag: String) -> Entity:
	tags.erase(tag)
	return self


## Check if entity has a tag
func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Destroy this entity and all its components
func destroy() -> void:
	active = false

	# Remove all components
	for component_name in _components.keys():
		var component: Component = _components[component_name]
		component._on_removed()

	_components.clear()
	destroyed.emit()

	# Notify world to remove entity
	if world:
		world.remove_entity(self)
