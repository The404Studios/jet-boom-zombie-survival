## Component - Base class for all ECS components
## Components are pure data containers with minimal logic
## They store state but don't implement behavior (that's what Systems do)
class_name Component
extends RefCounted

## Reference to the entity this component belongs to
var entity: Entity = null

## Whether this component is enabled
var enabled: bool = true


## Override this to return the component's unique name
func get_component_name() -> String:
	return "Component"


## Called when the component is added to an entity
func _on_added() -> void:
	pass


## Called when the component is removed from an entity
func _on_removed() -> void:
	pass


## Called every frame to update the component (optional)
func _process(_delta: float) -> void:
	pass


## Called every physics frame to update the component (optional)
func _physics_process(_delta: float) -> void:
	pass


## Serialize component data to dictionary
func serialize() -> Dictionary:
	return {
		"enabled": enabled
	}


## Deserialize component data from dictionary
func deserialize(data: Dictionary) -> void:
	enabled = data.get("enabled", true)


## Get entity ID (convenience method)
func get_entity_id() -> int:
	return entity.id if entity else -1


## Get another component from the same entity
func get_sibling_component(component_name: String) -> Component:
	if entity:
		return entity.get_component(component_name)
	return null
