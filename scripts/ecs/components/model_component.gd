## ModelComponent - Stores 3D model/mesh data and visual properties
## Manages the visual representation of an entity
class_name ModelComponent
extends Component

## Path to the model resource (GLB, GLTF, etc.)
var model_path: String = ""

## The loaded model scene
var model_scene: PackedScene = null

## The instantiated model node
var model_instance: Node3D = null

## Material override
var material_override: Material = null

## Tint color for the model
var tint_color: Color = Color.WHITE

## Emission color (for glowing effects)
var emission_color: Color = Color.BLACK

## Emission strength
var emission_strength: float = 0.0

## Model scale multiplier
var model_scale: Vector3 = Vector3.ONE

## Model offset from entity position
var model_offset: Vector3 = Vector3.ZERO

## Model rotation offset
var model_rotation_offset: Vector3 = Vector3.ZERO

## Whether the model is visible
var visible: bool = true

## Whether to cast shadows
var cast_shadows: bool = true

## Animation player reference
var animation_player: AnimationPlayer = null

## Current animation name
var current_animation: String = ""

## Animation speed multiplier
var animation_speed: float = 1.0

## Whether animation is looping
var animation_looping: bool = true

## Skeleton reference (for armature-based models)
var skeleton: Skeleton3D = null

## Mesh instances in the model
var mesh_instances: Array[MeshInstance3D] = []

## Signal when model is loaded
signal model_loaded()

## Signal when animation changes
signal animation_changed(animation_name: String)

## Signal when animation completes
signal animation_finished(animation_name: String)


func get_component_name() -> String:
	return "Model"


func _on_removed() -> void:
	unload_model()


## Load model from path
func load_model(path: String) -> bool:
	model_path = path

	if path.is_empty():
		return false

	# Try to load the scene
	var resource := ResourceLoader.load(path)
	if resource is PackedScene:
		model_scene = resource
		return true

	push_error("Failed to load model: %s" % path)
	return false


## Instantiate the loaded model
func instantiate(parent: Node3D) -> Node3D:
	if model_scene == null:
		if not model_path.is_empty():
			load_model(model_path)

	if model_scene == null:
		return null

	model_instance = model_scene.instantiate()
	parent.add_child(model_instance)

	# Apply initial properties
	_apply_visual_properties()

	# Find animation player and skeleton
	_find_animation_player()
	_find_skeleton()
	_find_mesh_instances()

	# Connect animation signals
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

	model_loaded.emit()
	return model_instance


## Unload and free the model instance
func unload_model() -> void:
	if model_instance and is_instance_valid(model_instance):
		model_instance.queue_free()
		model_instance = null

	animation_player = null
	skeleton = null
	mesh_instances.clear()


## Apply visual properties to the model
func _apply_visual_properties() -> void:
	if not model_instance:
		return

	model_instance.scale = model_scale
	model_instance.position = model_offset
	model_instance.rotation = model_rotation_offset
	model_instance.visible = visible

	# Apply material properties to all mesh instances
	_apply_materials()


## Apply materials to all mesh instances
func _apply_materials() -> void:
	if not model_instance:
		return

	var meshes := _get_all_mesh_instances(model_instance)
	for mesh_instance in meshes:
		if material_override:
			mesh_instance.material_override = material_override
		else:
			_apply_tint_to_mesh(mesh_instance)

		# Set shadow casting
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Apply tint color to a mesh instance
func _apply_tint_to_mesh(mesh_instance: MeshInstance3D) -> void:
	if tint_color == Color.WHITE and emission_color == Color.BLACK:
		return

	# Get or create material
	var mat: StandardMaterial3D = null

	if mesh_instance.get_surface_override_material_count() > 0:
		var existing := mesh_instance.get_surface_override_material(0)
		if existing is StandardMaterial3D:
			mat = existing.duplicate()
		else:
			mat = StandardMaterial3D.new()
	else:
		mat = StandardMaterial3D.new()

	# Apply tint
	mat.albedo_color = tint_color

	# Apply emission
	if emission_color != Color.BLACK and emission_strength > 0:
		mat.emission_enabled = true
		mat.emission = emission_color
		mat.emission_energy_multiplier = emission_strength
	else:
		mat.emission_enabled = false

	mesh_instance.set_surface_override_material(0, mat)


## Get all mesh instances in a node tree
func _get_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		result.append(node)

	for child in node.get_children():
		result.append_array(_get_all_mesh_instances(child))

	return result


## Find animation player in the model
func _find_animation_player() -> void:
	if not model_instance:
		return

	animation_player = _find_node_of_type(model_instance, "AnimationPlayer") as AnimationPlayer


## Find skeleton in the model
func _find_skeleton() -> void:
	if not model_instance:
		return

	skeleton = _find_node_of_type(model_instance, "Skeleton3D") as Skeleton3D


## Find all mesh instances
func _find_mesh_instances() -> void:
	mesh_instances.clear()
	if model_instance:
		mesh_instances = _get_all_mesh_instances(model_instance)


## Find a node of a specific type in a tree
func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node

	for child in node.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found

	return null


## Play an animation
func play_animation(animation_name: String, speed: float = -1.0) -> void:
	if not animation_player:
		return

	if not animation_player.has_animation(animation_name):
		push_warning("Animation not found: %s" % animation_name)
		return

	var play_speed := speed if speed >= 0 else animation_speed
	current_animation = animation_name
	animation_player.play(animation_name, -1, play_speed)
	animation_changed.emit(animation_name)


## Stop the current animation
func stop_animation() -> void:
	if animation_player:
		animation_player.stop()
	current_animation = ""


## Pause the current animation
func pause_animation() -> void:
	if animation_player:
		animation_player.pause()


## Resume the paused animation
func resume_animation() -> void:
	if animation_player:
		animation_player.play()


## Check if an animation is playing
func is_animation_playing(animation_name: String = "") -> bool:
	if not animation_player:
		return false

	if animation_name.is_empty():
		return animation_player.is_playing()

	return animation_player.is_playing() and animation_player.current_animation == animation_name


## Get list of available animations
func get_animation_list() -> PackedStringArray:
	if animation_player:
		return animation_player.get_animation_list()
	return PackedStringArray()


## Check if animation exists
func has_animation(animation_name: String) -> bool:
	if animation_player:
		return animation_player.has_animation(animation_name)
	return false


## Set visibility
func set_visible(is_visible: bool) -> void:
	visible = is_visible
	if model_instance:
		model_instance.visible = visible


## Set tint color
func set_tint(color: Color) -> void:
	tint_color = color
	_apply_materials()


## Set emission
func set_emission(color: Color, strength: float) -> void:
	emission_color = color
	emission_strength = strength
	_apply_materials()


## Animation finished callback
func _on_animation_finished(anim_name: StringName) -> void:
	animation_finished.emit(String(anim_name))


func serialize() -> Dictionary:
	var data := super.serialize()
	data["model_path"] = model_path
	data["tint_color"] = tint_color.to_html()
	data["emission_color"] = emission_color.to_html()
	data["emission_strength"] = emission_strength
	data["model_scale"] = {"x": model_scale.x, "y": model_scale.y, "z": model_scale.z}
	data["visible"] = visible
	data["cast_shadows"] = cast_shadows
	return data


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	model_path = data.get("model_path", "")
	tint_color = Color.from_string(data.get("tint_color", "#ffffff"), Color.WHITE)
	emission_color = Color.from_string(data.get("emission_color", "#000000"), Color.BLACK)
	emission_strength = data.get("emission_strength", 0.0)
	if data.has("model_scale"):
		var s: Dictionary = data["model_scale"]
		model_scale = Vector3(s.get("x", 1), s.get("y", 1), s.get("z", 1))
	visible = data.get("visible", true)
	cast_shadows = data.get("cast_shadows", true)
