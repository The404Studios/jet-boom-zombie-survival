extends RigidBody3D
class_name PickupableProp

# JetBoom-style pickupable prop that can be carried and nailed to surfaces
# Players pick up props to build barricades by nailing them together

signal picked_up(player: Node)
signal dropped(position: Vector3)
signal placed(surface: Node)
signal nailed(nail_count: int)
signal destroyed

@export var prop_name: String = "Prop"
@export var prop_weight: float = 10.0  # Affects carry speed
@export var max_health: float = 100.0
@export var can_be_nailed: bool = true
@export var nail_slots: int = 4  # How many nails to fully secure

# Prop state
enum PropState { WORLD, CARRIED, PLACED, NAILED }
var current_state: PropState = PropState.WORLD

var current_health: float = 100.0
var nails_attached: int = 0
var carrying_player: Node = null
var nailed_to: Node = null  # Surface or prop this is nailed to
var is_highlighted: bool = false

# Visual elements
var mesh: MeshInstance3D = null
var outline_mesh: MeshInstance3D = null
var collision_shape: CollisionShape3D = null
var interact_area: Area3D = null
var label: Label3D = null

# Nailing state
var nail_positions: Array[Vector3] = []
var nail_visuals: Array[Node3D] = []

# Physics state when picked up
var original_freeze_mode: int = 0
var original_collision_layer: int = 0
var original_collision_mask: int = 0

func _ready():
	add_to_group("props")
	add_to_group("pickupable")
	add_to_group("interactable")

	# Store original physics settings
	original_freeze_mode = freeze_mode
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask

	current_health = max_health

	# Find or create mesh
	for child in get_children():
		if child is MeshInstance3D:
			mesh = child
			break

	# Find collision shape
	for child in get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break

	# Create interact area for pickup detection
	_create_interact_area()

	# Create label
	_create_label()

	# Create outline for highlighting
	_create_outline()

func _create_interact_area():
	"""Create Area3D for pickup detection"""
	interact_area = Area3D.new()
	interact_area.name = "InteractArea"
	interact_area.collision_layer = 0
	interact_area.collision_mask = 2  # Player layer

	var area_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 1.5  # Pickup range
	area_shape.shape = sphere
	interact_area.add_child(area_shape)

	add_child(interact_area)

	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)

func _create_label():
	"""Create floating label"""
	label = Label3D.new()
	label.name = "PropLabel"
	label.text = prop_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 16
	label.position = Vector3(0, 1.5, 0)
	label.modulate = Color(1, 1, 1, 0.9)
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 3
	label.visible = false
	add_child(label)

func _create_outline():
	"""Create outline mesh for highlighting"""
	if not mesh or not mesh.mesh:
		return

	outline_mesh = MeshInstance3D.new()
	outline_mesh.name = "OutlineMesh"
	outline_mesh.mesh = mesh.mesh
	outline_mesh.scale = Vector3(1.02, 1.02, 1.02)
	outline_mesh.visible = false

	var outline_mat = StandardMaterial3D.new()
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.5)
	outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	outline_mesh.material_override = outline_mat

	add_child(outline_mesh)

# ============================================
# PICKUP / CARRY SYSTEM
# ============================================

func can_pickup() -> bool:
	"""Check if prop can be picked up"""
	return current_state == PropState.WORLD or current_state == PropState.PLACED

func pickup(player: Node) -> bool:
	"""Pick up prop - called by player"""
	if not can_pickup():
		return false

	# If nailed, need to unnail first
	if current_state == PropState.NAILED:
		return false

	carrying_player = player
	current_state = PropState.CARRIED

	# Disable physics
	freeze = true
	collision_layer = 0
	collision_mask = 0

	# Remove from world
	var old_parent = get_parent()
	old_parent.remove_child(self)

	# Add to player's prop holder
	if player.has_node("PropHolder"):
		player.get_node("PropHolder").add_child(self)
		position = Vector3(0, 0, -1.5)  # In front of player
		rotation = Vector3.ZERO
	else:
		# Fallback: Add to camera
		if player.has_node("Camera3D"):
			player.get_node("Camera3D").add_child(self)
			position = Vector3(0, -0.3, -1.5)
			rotation = Vector3.ZERO
		else:
			# Can't carry, put back
			old_parent.add_child(self)
			return false

	# Hide label and outline while carried
	if label:
		label.visible = false
	if outline_mesh:
		outline_mesh.visible = false

	# Play pickup sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("prop_pickup", global_position, 0.6)

	picked_up.emit(player)
	return true

func drop() -> bool:
	"""Drop the prop at current position"""
	if current_state != PropState.CARRIED:
		return false

	if not carrying_player:
		return false

	var drop_pos = global_position
	var drop_rot = global_rotation

	# Remove from player
	var old_parent = get_parent()
	old_parent.remove_child(self)

	# Add back to world
	var world = carrying_player.get_parent()
	world.add_child(self)
	global_position = drop_pos
	global_rotation = drop_rot

	# Re-enable physics
	freeze = false
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask

	current_state = PropState.WORLD
	carrying_player = null

	# Play drop sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("prop_drop", global_position, 0.5)

	dropped.emit(global_position)
	return true

func place(surface: Node = null) -> bool:
	"""Place prop at current position (without physics)"""
	if current_state != PropState.CARRIED:
		return false

	if not carrying_player:
		return false

	var place_pos = global_position
	var place_rot = global_rotation

	# Adjust position to be on ground/surface
	place_pos.y = _find_ground_height(place_pos)

	# Remove from player
	var old_parent = get_parent()
	old_parent.remove_child(self)

	# Add back to world
	var world = carrying_player.get_parent()
	world.add_child(self)
	global_position = place_pos
	global_rotation = place_rot

	# Keep frozen (placed but not physics-enabled)
	freeze = true
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask

	current_state = PropState.PLACED
	nailed_to = surface
	carrying_player = null

	# Add to barricade group for zombie targeting
	add_to_group("barricades")
	add_to_group("zombie_targets")

	# Play place sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("prop_place", global_position, 0.6)

	placed.emit(surface)
	return true

func _find_ground_height(pos: Vector3) -> float:
	"""Raycast to find ground below position"""
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 1, 0),
		pos - Vector3(0, 10, 0)
	)
	query.exclude = [self]
	query.collision_mask = 1  # World layer

	var result = space_state.intersect_ray(query)
	if result:
		# Get shape height
		var height_offset = 0.5
		if collision_shape and collision_shape.shape is BoxShape3D:
			height_offset = collision_shape.shape.size.y / 2
		return result.position.y + height_offset

	return pos.y

# ============================================
# NAILING SYSTEM
# ============================================

func can_nail() -> bool:
	"""Check if prop can be nailed"""
	return can_be_nailed and current_state == PropState.PLACED and nails_attached < nail_slots

func add_nail() -> bool:
	"""Add a nail to secure the prop"""
	if not can_nail():
		return false

	nails_attached += 1

	# Increase health with each nail
	var nail_health_bonus = max_health * 0.25
	current_health = min(current_health + nail_health_bonus, max_health * 2.0)

	# Create nail visual
	_spawn_nail_visual()

	# Play hammer sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("hammer", global_position, 0.8)

	# Spawn wood particles
	if has_node("/root/VFXManager"):
		var nail_pos = global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.3, 0.8), randf_range(-0.3, 0.3))
		get_node("/root/VFXManager").spawn_impact_effect(nail_pos, Vector3.UP, "wood")

	nailed.emit(nails_attached)

	# Check if fully nailed
	if nails_attached >= nail_slots:
		_become_nailed()

	return true

func _become_nailed():
	"""Prop is now fully nailed down"""
	current_state = PropState.NAILED

	# Make it a solid static obstacle
	freeze = true

	# Boost max health
	max_health *= 1.5
	current_health = max_health

	# Play completion sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("hammer_complete", global_position, 0.7)

	# Visual feedback
	if mesh and mesh.material_override is StandardMaterial3D:
		mesh.material_override.emission_enabled = true
		mesh.material_override.emission = Color(0.1, 0.3, 0.1)
		mesh.material_override.emission_energy_multiplier = 0.3

func _spawn_nail_visual():
	"""Spawn a nail visual at a random position on the prop"""
	var nail = MeshInstance3D.new()
	var nail_mesh = CylinderMesh.new()
	nail_mesh.top_radius = 0.02
	nail_mesh.bottom_radius = 0.02
	nail_mesh.height = 0.15
	nail.mesh = nail_mesh

	var nail_mat = StandardMaterial3D.new()
	nail_mat.albedo_color = Color(0.5, 0.5, 0.5)
	nail_mat.metallic = 0.9
	nail.material_override = nail_mat

	# Random position on prop surface
	var offset = Vector3(
		randf_range(-0.4, 0.4),
		randf_range(0.2, 0.8),
		randf_range(-0.4, 0.4)
	)
	nail.position = offset
	nail.rotation = Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))

	add_child(nail)
	nail_visuals.append(nail)
	nail_positions.append(offset)

func get_nail_progress() -> float:
	"""Get nailing progress (0.0 - 1.0)"""
	return float(nails_attached) / float(nail_slots) if nail_slots > 0 else 1.0

# ============================================
# DAMAGE
# ============================================

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	"""Take damage from zombies"""
	current_health -= amount
	current_health = max(current_health, 0)

	# Play damage sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("wood_hit", global_position, 0.5)

	# Update visual
	_update_damage_visual()

	if current_health <= 0:
		_destroy()

func _update_damage_visual():
	"""Update prop appearance based on damage"""
	var health_percent = current_health / max_health if max_health > 0 else 0.0

	if mesh and mesh.material_override is StandardMaterial3D:
		# Darken based on damage
		var mat = mesh.material_override
		mat.albedo_color = Color(health_percent, health_percent * 0.8, health_percent * 0.6)

func _destroy():
	"""Destroy the prop"""
	destroyed.emit()

	# Play destruction sound
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sound_3d("wood_break", global_position, 1.0)

	# Spawn debris
	if has_node("/root/VFXManager"):
		get_node("/root/VFXManager").spawn_impact_effect(global_position, Vector3.UP, "wood")

	# Could spawn smaller debris props here

	queue_free()

# ============================================
# INTERACTION DETECTION
# ============================================

func _on_body_entered(body: Node3D):
	if body.is_in_group("player") and can_pickup():
		highlight(true)

func _on_body_exited(body: Node3D):
	if body.is_in_group("player"):
		highlight(false)

func highlight(enable: bool):
	"""Highlight prop when player is nearby"""
	is_highlighted = enable

	if outline_mesh:
		outline_mesh.visible = enable

	if label:
		if enable and current_state == PropState.WORLD:
			label.text = "[E] Pick up %s" % prop_name
			label.visible = true
		elif enable and current_state == PropState.PLACED:
			if can_nail():
				label.text = "[E] Nail %s (%d/%d)" % [prop_name, nails_attached, nail_slots]
			else:
				label.text = "%s (Secured)" % prop_name
			label.visible = true
		else:
			label.visible = false

func interact(player: Node) -> bool:
	"""Main interaction handler - called by player"""
	match current_state:
		PropState.WORLD:
			return pickup(player)
		PropState.CARRIED:
			return place()
		PropState.PLACED:
			if can_nail():
				return add_nail()
		PropState.NAILED:
			# Can't interact with nailed props
			return false

	return false

# ============================================
# UTILITY
# ============================================

func get_interact_prompt() -> String:
	"""Get interaction prompt text"""
	match current_state:
		PropState.WORLD:
			return "[E] Pick up %s" % prop_name
		PropState.CARRIED:
			return "[E] Place %s / [Q] Drop" % prop_name
		PropState.PLACED:
			if can_nail():
				return "[E] Hold to Nail (%d/%d)" % [nails_attached, nail_slots]
			else:
				return "%s (Secured)" % prop_name
		PropState.NAILED:
			return "%s (Nailed Down)" % prop_name

	return ""

func get_state_name() -> String:
	match current_state:
		PropState.WORLD: return "World"
		PropState.CARRIED: return "Carried"
		PropState.PLACED: return "Placed"
		PropState.NAILED: return "Nailed"
	return "Unknown"
