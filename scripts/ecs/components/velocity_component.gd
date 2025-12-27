## VelocityComponent - Stores linear and angular velocity data
## Used by the movement system to update entity positions
class_name VelocityComponent
extends Component

## Linear velocity (units per second)
var linear: Vector3 = Vector3.ZERO

## Angular velocity (radians per second)
var angular: Vector3 = Vector3.ZERO

## Maximum linear speed
var max_speed: float = 10.0

## Maximum angular speed
var max_angular_speed: float = 10.0

## Gravity multiplier (0 = no gravity, 1 = normal gravity)
var gravity_scale: float = 1.0

## Whether to apply gravity
var use_gravity: bool = true

## Friction/drag coefficient (0 = no friction, 1 = instant stop)
var friction: float = 0.0

## Angular friction/drag
var angular_friction: float = 0.5

## Acceleration for movement
var acceleration: float = 50.0

## Deceleration when no input
var deceleration: float = 30.0

## Whether entity is on ground (for jumping)
var is_grounded: bool = false

## Desired movement direction (normalized)
var move_direction: Vector3 = Vector3.ZERO


func get_component_name() -> String:
	return "Velocity"


## Set linear velocity, clamped to max speed
func set_linear(vel: Vector3) -> void:
	linear = vel
	if linear.length() > max_speed:
		linear = linear.normalized() * max_speed


## Add to linear velocity
func add_linear(vel: Vector3) -> void:
	linear += vel
	if linear.length() > max_speed:
		linear = linear.normalized() * max_speed


## Set angular velocity, clamped to max angular speed
func set_angular(vel: Vector3) -> void:
	angular = vel
	if angular.length() > max_angular_speed:
		angular = angular.normalized() * max_angular_speed


## Add to angular velocity
func add_angular(vel: Vector3) -> void:
	angular += vel
	if angular.length() > max_angular_speed:
		angular = angular.normalized() * max_angular_speed


## Get horizontal velocity (XZ plane)
func get_horizontal_velocity() -> Vector3:
	return Vector3(linear.x, 0, linear.z)


## Set horizontal velocity while preserving vertical
func set_horizontal_velocity(vel: Vector3) -> void:
	linear.x = vel.x
	linear.z = vel.z


## Get vertical velocity (Y axis)
func get_vertical_velocity() -> float:
	return linear.y


## Set vertical velocity while preserving horizontal
func set_vertical_velocity(vel: float) -> void:
	linear.y = vel


## Get the speed (magnitude of linear velocity)
func get_speed() -> float:
	return linear.length()


## Get horizontal speed
func get_horizontal_speed() -> float:
	return get_horizontal_velocity().length()


## Apply impulse (instant velocity change)
func apply_impulse(impulse: Vector3) -> void:
	add_linear(impulse)


## Apply angular impulse
func apply_angular_impulse(impulse: Vector3) -> void:
	add_angular(impulse)


## Stop all movement
func stop() -> void:
	linear = Vector3.ZERO
	angular = Vector3.ZERO
	move_direction = Vector3.ZERO


## Stop horizontal movement only
func stop_horizontal() -> void:
	linear.x = 0
	linear.z = 0


## Apply friction over delta time
func apply_friction(delta: float) -> void:
	if friction > 0:
		var factor := 1.0 - friction * delta
		linear.x *= factor
		linear.z *= factor

	if angular_friction > 0:
		angular *= (1.0 - angular_friction * delta)


func serialize() -> Dictionary:
	var data := super.serialize()
	data["linear"] = {"x": linear.x, "y": linear.y, "z": linear.z}
	data["angular"] = {"x": angular.x, "y": angular.y, "z": angular.z}
	data["max_speed"] = max_speed
	data["gravity_scale"] = gravity_scale
	data["use_gravity"] = use_gravity
	data["friction"] = friction
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	if data.has("linear"):
		var l: Dictionary = data["linear"]
		linear = Vector3(l.get("x", 0), l.get("y", 0), l.get("z", 0))
	if data.has("angular"):
		var a: Dictionary = data["angular"]
		angular = Vector3(a.get("x", 0), a.get("y", 0), a.get("z", 0))
	max_speed = data.get("max_speed", 10.0)
	gravity_scale = data.get("gravity_scale", 1.0)
	use_gravity = data.get("use_gravity", true)
	friction = data.get("friction", 0.0)
