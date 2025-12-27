## ColliderComponent - Stores collision shape and physics properties
## Used for detecting collisions and physics interactions
class_name ColliderComponent
extends Component

## Collision shape type
enum ShapeType {
	NONE,
	CAPSULE,
	BOX,
	SPHERE,
	CYLINDER,
	CUSTOM
}

## Current shape type
var shape_type: ShapeType = ShapeType.CAPSULE

## Capsule properties
var capsule_radius: float = 0.4
var capsule_height: float = 1.8

## Box properties
var box_size: Vector3 = Vector3(1, 1, 1)

## Sphere properties
var sphere_radius: float = 0.5

## Cylinder properties
var cylinder_radius: float = 0.5
var cylinder_height: float = 1.0

## Custom shape resource
var custom_shape: Shape3D = null

## Physics layers (bit mask)
var collision_layer: int = 1

## Physics masks (what this collides with)
var collision_mask: int = 1

## Whether collision is enabled
var collision_enabled: bool = true

## Linked CharacterBody3D
var character_body: CharacterBody3D = null

## Linked RigidBody3D
var rigid_body: RigidBody3D = null

## Linked Area3D (for triggers)
var area: Area3D = null

## Linked CollisionShape3D
var collision_shape: CollisionShape3D = null

## Whether this is a trigger (no physical collision)
var is_trigger: bool = false

## Raycast for ground detection
var ground_ray: RayCast3D = null

## Ground detection distance
var ground_check_distance: float = 0.1

## Bodies currently overlapping (for triggers)
var overlapping_bodies: Array[Node3D] = []

## Signal when collision detected
signal collision_entered(body: Node3D)

## Signal when collision exited
signal collision_exited(body: Node3D)

## Signal for area triggers
signal trigger_entered(body: Node3D)

## Signal for area triggers
signal trigger_exited(body: Node3D)


func get_component_name() -> String:
	return "Collider"


func _on_removed() -> void:
	# Clean up physics nodes if we created them
	if collision_shape and is_instance_valid(collision_shape):
		collision_shape.queue_free()
	if area and is_instance_valid(area):
		area.queue_free()


## Create the collision shape based on type
func create_shape() -> Shape3D:
	match shape_type:
		ShapeType.CAPSULE:
			var capsule := CapsuleShape3D.new()
			capsule.radius = capsule_radius
			capsule.height = capsule_height
			return capsule

		ShapeType.BOX:
			var box := BoxShape3D.new()
			box.size = box_size
			return box

		ShapeType.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = sphere_radius
			return sphere

		ShapeType.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = cylinder_radius
			cylinder.height = cylinder_height
			return cylinder

		ShapeType.CUSTOM:
			return custom_shape

	return null


## Setup collision for a CharacterBody3D
func setup_character_body(body: CharacterBody3D) -> void:
	character_body = body
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask

	# Create collision shape if needed
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.shape = create_shape()
		body.add_child(collision_shape)
	else:
		collision_shape.shape = create_shape()

	collision_shape.disabled = not collision_enabled

	# Setup ground ray
	_setup_ground_ray(body)


## Setup collision for a RigidBody3D
func setup_rigid_body(body: RigidBody3D) -> void:
	rigid_body = body
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask

	# Create collision shape if needed
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.shape = create_shape()
		body.add_child(collision_shape)
	else:
		collision_shape.shape = create_shape()

	collision_shape.disabled = not collision_enabled

	# Connect signals
	body.body_entered.connect(_on_body_entered)
	body.body_exited.connect(_on_body_exited)


## Setup an Area3D trigger
func setup_area_trigger(parent: Node3D) -> Area3D:
	if not area:
		area = Area3D.new()
		parent.add_child(area)

	area.collision_layer = collision_layer
	area.collision_mask = collision_mask

	# Create collision shape for area
	var area_shape := CollisionShape3D.new()
	area_shape.shape = create_shape()
	area.add_child(area_shape)

	# Connect signals
	area.body_entered.connect(_on_trigger_body_entered)
	area.body_exited.connect(_on_trigger_body_exited)

	is_trigger = true
	return area


## Setup ground detection raycast
func _setup_ground_ray(parent: Node3D) -> void:
	if ground_ray:
		return

	ground_ray = RayCast3D.new()
	ground_ray.target_position = Vector3(0, -ground_check_distance, 0)
	ground_ray.collision_mask = collision_mask
	ground_ray.enabled = true
	parent.add_child(ground_ray)


## Check if on ground
func is_on_ground() -> bool:
	if character_body:
		return character_body.is_on_floor()

	if ground_ray:
		return ground_ray.is_colliding()

	return false


## Get ground normal
func get_ground_normal() -> Vector3:
	if character_body:
		return character_body.get_floor_normal()

	if ground_ray and ground_ray.is_colliding():
		return ground_ray.get_collision_normal()

	return Vector3.UP


## Set collision layer
func set_layer(layer: int) -> void:
	collision_layer = layer
	if character_body:
		character_body.collision_layer = layer
	if rigid_body:
		rigid_body.collision_layer = layer
	if area:
		area.collision_layer = layer


## Set collision mask
func set_mask(mask: int) -> void:
	collision_mask = mask
	if character_body:
		character_body.collision_mask = mask
	if rigid_body:
		rigid_body.collision_mask = mask
	if area:
		area.collision_mask = mask


## Enable or disable collision
func set_collision_enabled(is_enabled: bool) -> void:
	collision_enabled = is_enabled
	if collision_shape:
		collision_shape.disabled = not is_enabled


## Resize the collider
func resize_capsule(radius: float, height: float) -> void:
	shape_type = ShapeType.CAPSULE
	capsule_radius = radius
	capsule_height = height
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		capsule.radius = radius
		capsule.height = height


## Resize box collider
func resize_box(size: Vector3) -> void:
	shape_type = ShapeType.BOX
	box_size = size
	if collision_shape and collision_shape.shape is BoxShape3D:
		var box := collision_shape.shape as BoxShape3D
		box.size = size


## Resize sphere collider
func resize_sphere(radius: float) -> void:
	shape_type = ShapeType.SPHERE
	sphere_radius = radius
	if collision_shape and collision_shape.shape is SphereShape3D:
		var sphere := collision_shape.shape as SphereShape3D
		sphere.radius = radius


## Body entered callback
func _on_body_entered(body: Node3D) -> void:
	if not overlapping_bodies.has(body):
		overlapping_bodies.append(body)
	collision_entered.emit(body)


## Body exited callback
func _on_body_exited(body: Node3D) -> void:
	overlapping_bodies.erase(body)
	collision_exited.emit(body)


## Trigger body entered
func _on_trigger_body_entered(body: Node3D) -> void:
	if not overlapping_bodies.has(body):
		overlapping_bodies.append(body)
	trigger_entered.emit(body)


## Trigger body exited
func _on_trigger_body_exited(body: Node3D) -> void:
	overlapping_bodies.erase(body)
	trigger_exited.emit(body)


## Get all overlapping bodies
func get_overlapping_bodies() -> Array[Node3D]:
	return overlapping_bodies


## Check if overlapping with specific body
func is_overlapping(body: Node3D) -> bool:
	return overlapping_bodies.has(body)


func serialize() -> Dictionary:
	var data := super.serialize()
	data["shape_type"] = shape_type
	data["capsule_radius"] = capsule_radius
	data["capsule_height"] = capsule_height
	data["box_size"] = {"x": box_size.x, "y": box_size.y, "z": box_size.z}
	data["sphere_radius"] = sphere_radius
	data["collision_layer"] = collision_layer
	data["collision_mask"] = collision_mask
	data["is_trigger"] = is_trigger
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	shape_type = data.get("shape_type", ShapeType.CAPSULE)
	capsule_radius = data.get("capsule_radius", 0.4)
	capsule_height = data.get("capsule_height", 1.8)
	if data.has("box_size"):
		var s: Dictionary = data["box_size"]
		box_size = Vector3(s.get("x", 1), s.get("y", 1), s.get("z", 1))
	sphere_radius = data.get("sphere_radius", 0.5)
	collision_layer = data.get("collision_layer", 1)
	collision_mask = data.get("collision_mask", 1)
	is_trigger = data.get("is_trigger", false)
