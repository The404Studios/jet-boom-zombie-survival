## RenderSystem - Processes entity visual representation
## Handles model instantiation, animation, and visual updates
class_name RenderSystem
extends System

## Priority is low (runs after other systems)
var priority: int = 50

## Parent node for entity visuals
var visual_parent: Node3D = null


func get_system_name() -> String:
	return "RenderSystem"


func get_required_components() -> Array[String]:
	return ["Transform", "Model"]


func get_optional_components() -> Array[String]:
	return ["Health", "StatusEffect"]


func _on_added() -> void:
	# Find or create visual parent
	if world and not visual_parent:
		visual_parent = Node3D.new()
		visual_parent.name = "EntityVisuals"
		world.add_child(visual_parent)


func _on_removed() -> void:
	if visual_parent and is_instance_valid(visual_parent):
		visual_parent.queue_free()


func _on_entity_added(entity: Entity) -> void:
	_instantiate_model(entity)


func _on_entity_removed(entity: Entity) -> void:
	_remove_model(entity)


func process_entity(entity: Entity, _delta: float) -> void:
	var transform_comp := entity.get_component("Transform") as TransformComponent
	var model_comp := entity.get_component("Model") as ModelComponent

	if not transform_comp or not model_comp:
		return

	# Update model position/rotation from transform
	if model_comp.model_instance and is_instance_valid(model_comp.model_instance):
		model_comp.model_instance.global_position = transform_comp.position + model_comp.model_offset
		model_comp.model_instance.rotation = transform_comp.rotation + model_comp.model_rotation_offset
		model_comp.model_instance.scale = model_comp.model_scale

	# Update visual effects based on status
	_update_visual_effects(entity, model_comp)


## Instantiate model for entity
func _instantiate_model(entity: Entity) -> void:
	var model_comp := entity.get_component("Model") as ModelComponent
	var transform_comp := entity.get_component("Transform") as TransformComponent

	if not model_comp or not transform_comp:
		return

	# Don't re-instantiate if already exists
	if model_comp.model_instance and is_instance_valid(model_comp.model_instance):
		return

	# Get parent for model
	var parent := visual_parent if visual_parent else world

	# Try to instantiate model
	if model_comp.model_path != "":
		model_comp.instantiate(parent)
	elif model_comp.model_scene:
		model_comp.instantiate(parent)

	# Set initial position
	if model_comp.model_instance:
		model_comp.model_instance.global_position = transform_comp.position
		model_comp.model_instance.rotation = transform_comp.rotation

		# Link transform to model node
		transform_comp.node_3d = model_comp.model_instance


## Remove model for entity
func _remove_model(entity: Entity) -> void:
	var model_comp := entity.get_component("Model") as ModelComponent
	if model_comp:
		model_comp.unload_model()

	var transform_comp := entity.get_component("Transform") as TransformComponent
	if transform_comp:
		transform_comp.node_3d = null


## Update visual effects based on entity state
func _update_visual_effects(entity: Entity, model_comp: ModelComponent) -> void:
	var health_comp := entity.get_component("Health") as HealthComponent
	var status_comp := entity.get_component("StatusEffect") as StatusEffectComponent

	# Low health visual (red tint)
	if health_comp and health_comp.get_health_percent() < 0.25:
		_apply_damage_tint(model_comp)
	else:
		_clear_damage_tint(model_comp)

	# Status effect visuals
	if status_comp:
		_apply_status_effect_visuals(model_comp, status_comp)


## Apply damage tint to model
func _apply_damage_tint(model_comp: ModelComponent) -> void:
	if model_comp.tint_color != Color(1, 0.7, 0.7):
		model_comp.set_tint(Color(1, 0.7, 0.7))


## Clear damage tint
func _clear_damage_tint(model_comp: ModelComponent) -> void:
	if model_comp.tint_color == Color(1, 0.7, 0.7):
		model_comp.set_tint(Color.WHITE)


## Apply status effect visuals
func _apply_status_effect_visuals(model_comp: ModelComponent, status_comp: StatusEffectComponent) -> void:
	# Poison effect - green tint
	if status_comp.has_effect("poison"):
		model_comp.set_emission(Color(0, 1, 0), 0.3)
		return

	# Burn effect - orange emission
	if status_comp.has_effect("burn"):
		model_comp.set_emission(Color(1, 0.5, 0), 0.5)
		return

	# Freeze effect - blue tint
	if status_comp.has_effect("freeze") or status_comp.has_effect("slow"):
		model_comp.set_emission(Color(0.3, 0.5, 1), 0.3)
		return

	# Clear emission if no active effects
	if model_comp.emission_strength > 0:
		model_comp.set_emission(Color.BLACK, 0.0)


## Create a procedural model for entity (placeholder)
func create_placeholder_model(entity: Entity, shape: String = "capsule",
		color: Color = Color.GRAY) -> void:

	var model_comp := entity.get_component("Model") as ModelComponent
	var transform_comp := entity.get_component("Transform") as TransformComponent

	if not model_comp or not transform_comp:
		return

	# Create mesh instance
	var mesh_instance := MeshInstance3D.new()

	match shape:
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.4
			capsule.height = 1.8
			mesh_instance.mesh = capsule
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(1, 1, 1)
			mesh_instance.mesh = box
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			mesh_instance.mesh = sphere

	# Apply color material
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material

	# Add to scene
	var parent := visual_parent if visual_parent else world
	parent.add_child(mesh_instance)

	# Store reference
	model_comp.model_instance = mesh_instance
	model_comp.tint_color = color
	transform_comp.node_3d = mesh_instance


## Get the visual node for an entity
func get_visual_node(entity: Entity) -> Node3D:
	var model_comp := entity.get_component("Model") as ModelComponent
	if model_comp:
		return model_comp.model_instance
	return null


## Set model visibility
func set_entity_visible(entity: Entity, is_visible: bool) -> void:
	var model_comp := entity.get_component("Model") as ModelComponent
	if model_comp:
		model_comp.set_visible(is_visible)


## Play animation on entity
func play_animation(entity: Entity, animation_name: String, speed: float = 1.0) -> void:
	var model_comp := entity.get_component("Model") as ModelComponent
	if model_comp:
		model_comp.play_animation(animation_name, speed)
