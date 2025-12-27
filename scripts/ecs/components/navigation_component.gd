## NavigationComponent - Stores pathfinding and navigation data
## Used by AI entities for movement and target following
class_name NavigationComponent
extends Component

## Target position to navigate to
var target_position: Vector3 = Vector3.ZERO

## Target entity to follow
var target_entity: Entity = null

## Whether navigation is active
var is_navigating: bool = false

## Navigation agent reference
var nav_agent: NavigationAgent3D = null

## Path update interval (seconds)
var path_update_interval: float = 0.25

## Time since last path update
var path_update_timer: float = 0.0

## Detection range for targets
var detection_range: float = 20.0

## Attack range (stop navigating within this range)
var attack_range: float = 2.0

## Avoidance enabled
var avoidance_enabled: bool = true

## Avoidance radius
var avoidance_radius: float = 0.5

## Avoidance priority (lower = more important)
var avoidance_priority: float = 1.0

## Current path waypoints
var current_path: PackedVector3Array = PackedVector3Array()

## Current waypoint index
var current_waypoint: int = 0

## Whether the path is complete
var path_complete: bool = false

## Whether target is in range
var target_in_range: bool = false

## Whether target is in attack range
var target_in_attack_range: bool = false

## Last known target position
var last_known_target_position: Vector3 = Vector3.ZERO

## Navigation layer mask
var navigation_layers: int = 1

## Signal when target reached
signal target_reached()

## Signal when target lost
signal target_lost()

## Signal when path updated
signal path_updated()

## Signal when target enters attack range
signal entered_attack_range()

## Signal when target exits attack range
signal exited_attack_range()


func get_component_name() -> String:
	return "Navigation"


func _on_removed() -> void:
	if nav_agent and is_instance_valid(nav_agent):
		nav_agent.queue_free()


## Setup navigation agent
func setup_nav_agent(parent: Node3D) -> NavigationAgent3D:
	if not nav_agent:
		nav_agent = NavigationAgent3D.new()
		parent.add_child(nav_agent)

	# Configure agent
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = attack_range
	nav_agent.navigation_layers = navigation_layers

	# Configure avoidance
	nav_agent.avoidance_enabled = avoidance_enabled
	nav_agent.radius = avoidance_radius
	nav_agent.avoidance_priority = avoidance_priority

	# Connect signals
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	nav_agent.navigation_finished.connect(_on_navigation_finished)

	return nav_agent


## Set target position
func set_target(position: Vector3) -> void:
	target_position = position
	target_entity = null
	is_navigating = true
	path_complete = false

	if nav_agent:
		nav_agent.target_position = position


## Set target entity to follow
func set_target_entity(target: Entity) -> void:
	target_entity = target
	is_navigating = true
	path_complete = false

	# Get initial target position
	var transform_comp := target.get_component("Transform") as TransformComponent
	if transform_comp:
		target_position = transform_comp.position
		last_known_target_position = target_position
		if nav_agent:
			nav_agent.target_position = target_position


## Stop navigation
func stop_navigation() -> void:
	is_navigating = false
	target_entity = null
	path_complete = true


## Update navigation (called by AISystem)
func update_navigation(delta: float, current_position: Vector3) -> void:
	if not is_navigating or not nav_agent:
		return

	path_update_timer += delta

	# Update target position if following an entity
	if target_entity:
		var transform_comp := target_entity.get_component("Transform") as TransformComponent
		if transform_comp:
			var new_target := transform_comp.position
			var distance := current_position.distance_to(new_target)

			# Check detection range
			target_in_range = distance <= detection_range

			# Check attack range
			var was_in_attack_range := target_in_attack_range
			target_in_attack_range = distance <= attack_range

			if target_in_attack_range and not was_in_attack_range:
				entered_attack_range.emit()
			elif not target_in_attack_range and was_in_attack_range:
				exited_attack_range.emit()

			# Update path periodically or if target moved significantly
			if target_in_range:
				last_known_target_position = new_target
				if path_update_timer >= path_update_interval or new_target.distance_to(target_position) > 1.0:
					target_position = new_target
					nav_agent.target_position = target_position
					path_update_timer = 0.0
					path_updated.emit()
		else:
			# Target entity no longer has transform - lost target
			target_lost.emit()
			stop_navigation()


## Get next movement direction
func get_next_direction(current_position: Vector3) -> Vector3:
	if not nav_agent or not is_navigating:
		return Vector3.ZERO

	if nav_agent.is_navigation_finished():
		return Vector3.ZERO

	var next_pos := nav_agent.get_next_path_position()
	var direction := current_position.direction_to(next_pos)
	direction.y = 0  # Keep movement horizontal
	return direction.normalized()


## Get distance to target
func get_distance_to_target(current_position: Vector3) -> float:
	return current_position.distance_to(target_position)


## Check if navigation is complete
func is_navigation_complete() -> bool:
	if nav_agent:
		return nav_agent.is_navigation_finished()
	return path_complete


## Check if target is reachable
func is_target_reachable() -> bool:
	if nav_agent:
		return nav_agent.is_target_reachable()
	return true


## Set avoidance velocity (for RVO)
func set_avoidance_velocity(velocity: Vector3) -> void:
	if nav_agent and avoidance_enabled:
		nav_agent.velocity = velocity


## Velocity computed callback (for RVO avoidance)
var _computed_velocity: Vector3 = Vector3.ZERO

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_computed_velocity = safe_velocity


## Get avoidance-adjusted velocity
func get_computed_velocity() -> Vector3:
	return _computed_velocity


## Navigation finished callback
func _on_navigation_finished() -> void:
	path_complete = true
	target_reached.emit()


## Check if within attack range
func is_within_attack_range(current_position: Vector3) -> bool:
	return current_position.distance_to(target_position) <= attack_range


## Recalculate path
func recalculate_path() -> void:
	if nav_agent:
		nav_agent.target_position = target_position
		path_update_timer = 0.0
		path_updated.emit()


func serialize() -> Dictionary:
	var data := super.serialize()
	data["target_position"] = {
		"x": target_position.x,
		"y": target_position.y,
		"z": target_position.z
	}
	data["detection_range"] = detection_range
	data["attack_range"] = attack_range
	data["avoidance_enabled"] = avoidance_enabled
	data["avoidance_radius"] = avoidance_radius
	data["navigation_layers"] = navigation_layers
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	if data.has("target_position"):
		var t: Dictionary = data["target_position"]
		target_position = Vector3(t.get("x", 0), t.get("y", 0), t.get("z", 0))
	detection_range = data.get("detection_range", 20.0)
	attack_range = data.get("attack_range", 2.0)
	avoidance_enabled = data.get("avoidance_enabled", true)
	avoidance_radius = data.get("avoidance_radius", 0.5)
	navigation_layers = data.get("navigation_layers", 1)
