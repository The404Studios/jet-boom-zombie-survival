## ControllerComponent - Base class for all entity controllers
## Controllers define how an entity behaves and responds to input/AI
class_name ControllerComponent
extends Component

## Controller type enum
enum ControllerType {
	NONE,
	PLAYER,
	AI_ZOMBIE,
	AI_WANDERER,
	PROJECTILE,
	SCRIPTED
}

## Type of controller
var controller_type: ControllerType = ControllerType.NONE

## Whether controller is active
var controller_active: bool = true

## Movement input direction (normalized)
var input_direction: Vector3 = Vector3.ZERO

## Look direction / aim direction
var look_direction: Vector3 = Vector3.FORWARD

## Target position for AI
var target_position: Vector3 = Vector3.ZERO

## Target entity for AI
var target_entity: Entity = null

## Whether primary action is pressed (attack/fire)
var action_primary: bool = false

## Whether secondary action is pressed (aim/block)
var action_secondary: bool = false

## Whether special action is pressed (ability/sprint)
var action_special: bool = false

## Jump requested
var action_jump: bool = false

## Interaction requested
var action_interact: bool = false

## Reload requested
var action_reload: bool = false

## Current state name for state machines
var current_state: String = "idle"

## Previous state name
var previous_state: String = ""

## State time elapsed
var state_time: float = 0.0

## Signal when state changes
signal state_changed(new_state: String, old_state: String)

## Signal when action triggered
signal action_triggered(action_name: String)


func get_component_name() -> String:
	return "Controller"


## Update controller (called by system)
func update(delta: float) -> void:
	state_time += delta
	_update_controller(delta)


## Override this in subclasses to implement controller logic
func _update_controller(_delta: float) -> void:
	pass


## Change state
func change_state(new_state: String) -> void:
	if new_state == current_state:
		return

	previous_state = current_state
	current_state = new_state
	state_time = 0.0
	_on_state_changed(new_state, previous_state)
	state_changed.emit(new_state, previous_state)


## Override to handle state changes
func _on_state_changed(_new_state: String, _old_state: String) -> void:
	pass


## Trigger an action
func trigger_action(action_name: String) -> void:
	action_triggered.emit(action_name)


## Clear all input
func clear_input() -> void:
	input_direction = Vector3.ZERO
	action_primary = false
	action_secondary = false
	action_special = false
	action_jump = false
	action_interact = false
	action_reload = false


## Set movement direction
func set_movement(direction: Vector3) -> void:
	input_direction = direction.normalized() if direction.length() > 0.1 else Vector3.ZERO


## Set look/aim direction
func set_look(direction: Vector3) -> void:
	look_direction = direction.normalized() if direction.length() > 0.1 else Vector3.FORWARD


## Check if moving
func is_moving() -> bool:
	return input_direction.length() > 0.1


## Check if in specific state
func is_in_state(state: String) -> bool:
	return current_state == state


## Check if state time exceeds duration
func state_time_exceeds(duration: float) -> bool:
	return state_time >= duration


func serialize() -> Dictionary:
	var data := super.serialize()
	data["controller_type"] = controller_type
	data["current_state"] = current_state
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	controller_type = data.get("controller_type", ControllerType.NONE)
	current_state = data.get("current_state", "idle")
