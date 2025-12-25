extends Area3D
class_name CaptureSigil

# Capturable sigil that can be linked with others for teleportation
# Players must stand on the sigil to capture it

signal sigil_captured(sigil: CaptureSigil, team: int)
signal sigil_contested(sigil: CaptureSigil)
signal sigil_neutralized(sigil: CaptureSigil)
signal link_established(from_sigil: CaptureSigil, to_sigil: CaptureSigil)
signal link_broken(from_sigil: CaptureSigil, to_sigil: CaptureSigil)
signal teleport_started(player: Node, destination: CaptureSigil)
signal teleport_completed(player: Node, destination: CaptureSigil)

enum SigilState { NEUTRAL, CAPTURING, CAPTURED, CONTESTED }

@export var sigil_name: String = "Sigil"
@export var sigil_id: int = 0  # Unique identifier
@export var capture_time: float = 5.0  # Seconds to capture
@export var capture_radius: float = 4.0
@export var teleport_cooldown: float = 10.0
@export var link_cost: int = 50  # Sigils currency cost to link

# State
var current_state: SigilState = SigilState.NEUTRAL
var capture_progress: float = 0.0  # 0 to 1
var owning_team: int = -1  # -1 = neutral, 0+ = team id
var players_on_sigil: Array = []
var linked_sigils: Array = []  # Array of CaptureSigil references
var teleport_cooldowns: Dictionary = {}  # player_id -> time remaining

# Visual components
var base_mesh: MeshInstance3D
var capture_ring: MeshInstance3D
var link_beams: Array = []  # Visual beams to linked sigils
var sigil_light: OmniLight3D
var name_label: Label3D
var status_label: Label3D

# Colors
const COLOR_NEUTRAL = Color(0.5, 0.5, 0.5)
const COLOR_CAPTURING = Color(1.0, 0.8, 0.0)
const COLOR_CAPTURED = Color(0.2, 0.8, 0.2)
const COLOR_CONTESTED = Color(1.0, 0.3, 0.0)
const COLOR_LINK = Color(0.4, 0.6, 1.0)

func _ready():
	add_to_group("capture_sigil")
	add_to_group("sigil_network")
	add_to_group("interactable")

	# Set up collision
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create visuals
	_create_visuals()
	_update_visuals()

func _process(delta):
	# Update capture progress
	_process_capture(delta)

	# Update teleport cooldowns
	_update_cooldowns(delta)

	# Update link beam visuals
	_update_link_beams()

func _create_visuals():
	# Base platform
	base_mesh = MeshInstance3D.new()
	base_mesh.name = "BaseMesh"
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = capture_radius
	cylinder.bottom_radius = capture_radius + 0.5
	cylinder.height = 0.3
	cylinder.radial_segments = 32
	base_mesh.mesh = cylinder
	add_child(base_mesh)

	# Capture ring (shows progress)
	capture_ring = MeshInstance3D.new()
	capture_ring.name = "CaptureRing"
	var ring = TorusMesh.new()
	ring.inner_radius = capture_radius - 0.3
	ring.outer_radius = capture_radius
	ring.rings = 32
	ring.ring_segments = 32
	capture_ring.mesh = ring
	capture_ring.position.y = 0.2
	add_child(capture_ring)

	# Central pillar/crystal
	var pillar = MeshInstance3D.new()
	pillar.name = "Pillar"
	var pillar_mesh = CylinderMesh.new()
	pillar_mesh.top_radius = 0.3
	pillar_mesh.bottom_radius = 0.5
	pillar_mesh.height = 3.0
	pillar.mesh = pillar_mesh
	pillar.position.y = 1.5
	add_child(pillar)

	# Top crystal
	var crystal = MeshInstance3D.new()
	crystal.name = "Crystal"
	var prism = PrismMesh.new()
	prism.size = Vector3(1.0, 1.5, 1.0)
	crystal.mesh = prism
	crystal.position.y = 3.5
	crystal.rotation_degrees.x = 180
	add_child(crystal)

	# Light
	sigil_light = OmniLight3D.new()
	sigil_light.name = "SigilLight"
	sigil_light.light_energy = 3.0
	sigil_light.omni_range = 12.0
	sigil_light.omni_attenuation = 1.5
	sigil_light.position.y = 4.0
	add_child(sigil_light)

	# Name label
	name_label = Label3D.new()
	name_label.name = "NameLabel"
	name_label.text = sigil_name
	name_label.font_size = 48
	name_label.position.y = 5.5
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(name_label)

	# Status label
	status_label = Label3D.new()
	status_label.name = "StatusLabel"
	status_label.text = "NEUTRAL"
	status_label.font_size = 32
	status_label.position.y = 4.8
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(status_label)

	# Collision shape
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var sphere = SphereShape3D.new()
	sphere.radius = capture_radius
	col.shape = sphere
	add_child(col)

func _update_visuals():
	var color = COLOR_NEUTRAL
	var status_text = "NEUTRAL"

	match current_state:
		SigilState.NEUTRAL:
			color = COLOR_NEUTRAL
			status_text = "NEUTRAL"
		SigilState.CAPTURING:
			color = COLOR_CAPTURING
			status_text = "CAPTURING %.0f%%" % (capture_progress * 100)
		SigilState.CAPTURED:
			color = COLOR_CAPTURED
			status_text = "CAPTURED"
			if linked_sigils.size() > 0:
				status_text += " [%d LINKS]" % linked_sigils.size()
		SigilState.CONTESTED:
			color = COLOR_CONTESTED
			status_text = "CONTESTED"

	# Update materials
	_apply_color_to_mesh(base_mesh, color)
	_apply_color_to_mesh(capture_ring, color, true)

	# Update pillar and crystal
	var pillar = get_node_or_null("Pillar")
	var crystal = get_node_or_null("Crystal")
	if pillar:
		_apply_color_to_mesh(pillar, color)
	if crystal:
		_apply_color_to_mesh(crystal, color, true)

	# Update light
	if sigil_light:
		sigil_light.light_color = color

	# Update labels
	if name_label:
		name_label.modulate = color
	if status_label:
		status_label.text = status_text
		status_label.modulate = color

func _apply_color_to_mesh(mesh_instance: MeshInstance3D, color: Color, emissive: bool = false):
	if not mesh_instance:
		return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat

func _on_body_entered(body):
	if body.is_in_group("player"):
		players_on_sigil.append(body)
		_show_sigil_ui(body)

func _on_body_exited(body):
	if body.is_in_group("player"):
		players_on_sigil.erase(body)
		if body == players_on_sigil.size() == 0:
			_hide_sigil_ui()

func _show_sigil_ui(player: Node):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_interact_prompt"):
		var prompt = "[HOLD E] Capture Sigil"
		if current_state == SigilState.CAPTURED:
			if linked_sigils.size() > 0:
				prompt = "[F] Teleport  |  [G] Link to Another"
			else:
				prompt = "[G] Link to Another Sigil (Cost: %d Sigils)" % link_cost
		hud.show_interact_prompt(prompt)

func _hide_sigil_ui():
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("hide_interact_prompt"):
		hud.hide_interact_prompt()

func _process_capture(delta):
	if players_on_sigil.size() == 0:
		# No players - slowly decay capture progress
		if current_state == SigilState.CAPTURING:
			capture_progress -= delta * 0.2
			if capture_progress <= 0:
				capture_progress = 0
				current_state = SigilState.NEUTRAL
				_update_visuals()
		return

	# Check for capturing input from any player on sigil
	var is_capturing = false
	for player in players_on_sigil:
		if Input.is_action_pressed("interact"):  # Hold E to capture
			is_capturing = true
			break

	if current_state == SigilState.CAPTURED:
		# Handle teleport and link inputs
		_handle_captured_inputs()
		return

	if is_capturing:
		if current_state != SigilState.CAPTURING:
			current_state = SigilState.CAPTURING
			sigil_contested.emit(self)

		capture_progress += delta / capture_time

		if capture_progress >= 1.0:
			capture_progress = 1.0
			_complete_capture()

	_update_visuals()

func _handle_captured_inputs():
	for player in players_on_sigil:
		# Teleport - F key
		if Input.is_action_just_pressed("teleport"):
			_open_teleport_menu(player)
		# Link - G key
		elif Input.is_action_just_pressed("link_sigil"):
			_open_link_menu(player)

func _complete_capture():
	current_state = SigilState.CAPTURED
	owning_team = 0  # Player team

	# Award sigils
	var sigil_shop = get_tree().get_first_node_in_group("sigil_shop")
	if sigil_shop:
		sigil_shop.add_sigils(25, "Captured %s" % sigil_name)

	# Notify
	sigil_captured.emit(self, owning_team)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("%s captured!" % sigil_name)

	_update_visuals()

func _update_cooldowns(delta):
	var to_remove = []
	for player_id in teleport_cooldowns:
		teleport_cooldowns[player_id] -= delta
		if teleport_cooldowns[player_id] <= 0:
			to_remove.append(player_id)
	for player_id in to_remove:
		teleport_cooldowns.erase(player_id)

# ============================================
# LINKING SYSTEM
# ============================================

func can_link_to(other_sigil: CaptureSigil) -> bool:
	if other_sigil == self:
		return false
	if other_sigil.current_state != SigilState.CAPTURED:
		return false
	if other_sigil in linked_sigils:
		return false
	return true

func link_to(other_sigil: CaptureSigil, player: Node = null) -> bool:
	if not can_link_to(other_sigil):
		return false

	# Check cost
	var sigil_shop = get_tree().get_first_node_in_group("sigil_shop")
	if sigil_shop and sigil_shop.current_sigils < link_cost:
		if has_node("/root/ChatSystem"):
			get_node("/root/ChatSystem").emit_system_message("Not enough sigils to link! Need %d" % link_cost)
		return false

	# Spend sigils
	if sigil_shop:
		sigil_shop.spend_sigils(link_cost)

	# Create bidirectional link
	linked_sigils.append(other_sigil)
	other_sigil.linked_sigils.append(self)

	# Create visual beam
	_create_link_beam(other_sigil)
	other_sigil._create_link_beam(self)

	# Emit signals
	link_established.emit(self, other_sigil)
	other_sigil.link_established.emit(other_sigil, self)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Link established: %s <-> %s" % [sigil_name, other_sigil.sigil_name])

	_update_visuals()
	other_sigil._update_visuals()

	return true

func unlink_from(other_sigil: CaptureSigil):
	linked_sigils.erase(other_sigil)
	other_sigil.linked_sigils.erase(self)

	_remove_link_beam(other_sigil)
	other_sigil._remove_link_beam(self)

	link_broken.emit(self, other_sigil)
	other_sigil.link_broken.emit(other_sigil, self)

	_update_visuals()
	other_sigil._update_visuals()

func _create_link_beam(target: CaptureSigil):
	# Visual beam to linked sigil
	var beam = MeshInstance3D.new()
	beam.name = "LinkBeam_%d" % target.sigil_id
	beam.set_meta("target_sigil", target)

	var beam_mesh = CylinderMesh.new()
	beam_mesh.top_radius = 0.1
	beam_mesh.bottom_radius = 0.1
	beam_mesh.height = 1.0  # Will be scaled
	beam.mesh = beam_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = COLOR_LINK
	mat.emission_enabled = true
	mat.emission = COLOR_LINK
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.7
	beam.material_override = mat

	add_child(beam)
	link_beams.append(beam)

func _remove_link_beam(target: CaptureSigil):
	for beam in link_beams:
		if beam.get_meta("target_sigil") == target:
			link_beams.erase(beam)
			beam.queue_free()
			break

func _update_link_beams():
	for beam in link_beams:
		var target = beam.get_meta("target_sigil") as CaptureSigil
		if target and is_instance_valid(target):
			var direction = target.global_position - global_position
			var distance = direction.length()

			# Position beam at midpoint
			beam.global_position = global_position + direction * 0.5
			beam.global_position.y = 3.0  # Elevated

			# Scale to distance
			beam.scale.y = distance

			# Rotate to face target
			beam.look_at(target.global_position, Vector3.UP)
			beam.rotate_object_local(Vector3.RIGHT, PI / 2)

# ============================================
# TELEPORTATION SYSTEM
# ============================================

func get_available_destinations() -> Array:
	var destinations = []
	for sigil in linked_sigils:
		if is_instance_valid(sigil) and sigil.current_state == SigilState.CAPTURED:
			destinations.append(sigil)
	return destinations

func can_teleport(player: Node) -> bool:
	if current_state != SigilState.CAPTURED:
		return false
	if linked_sigils.size() == 0:
		return false

	var player_id = player.get_instance_id()
	if player_id in teleport_cooldowns:
		return false

	return true

func teleport_to(player: Node, destination: CaptureSigil):
	if not can_teleport(player):
		return

	if destination not in linked_sigils:
		return

	# Start teleport
	teleport_started.emit(player, destination)

	# Visual effect at start
	_spawn_teleport_effect(global_position)

	# Move player
	var target_pos = destination.global_position + Vector3(0, 1.5, 0)
	player.global_position = target_pos

	# Visual effect at destination
	destination._spawn_teleport_effect(destination.global_position)

	# Set cooldown
	var player_id = player.get_instance_id()
	teleport_cooldowns[player_id] = teleport_cooldown
	destination.teleport_cooldowns[player_id] = teleport_cooldown

	# Complete
	teleport_completed.emit(player, destination)

	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Teleported to %s" % destination.sigil_name)

func _spawn_teleport_effect(pos: Vector3):
	# Create particle effect
	var particles = GPUParticles3D.new()
	particles.global_position = pos + Vector3(0, 1, 0)
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 50
	particles.lifetime = 1.0

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 1.0
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 5.0
	material.gravity = Vector3(0, -2, 0)
	material.color = COLOR_LINK
	particles.process_material = material

	get_tree().current_scene.add_child(particles)

	# Auto-cleanup
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func _open_teleport_menu(player: Node):
	if not can_teleport(player):
		if has_node("/root/ChatSystem"):
			if linked_sigils.size() == 0:
				get_node("/root/ChatSystem").emit_system_message("No linked sigils to teleport to!")
			else:
				get_node("/root/ChatSystem").emit_system_message("Teleport on cooldown!")
		return

	# Get available destinations
	var destinations = get_available_destinations()
	if destinations.size() == 0:
		return

	# If only one destination, teleport directly
	if destinations.size() == 1:
		teleport_to(player, destinations[0])
		return

	# Show teleport selection UI
	var teleport_ui = get_tree().get_first_node_in_group("teleport_ui")
	if teleport_ui and teleport_ui.has_method("show_destinations"):
		teleport_ui.show_destinations(self, destinations, player)
	else:
		# Fallback: teleport to first destination
		teleport_to(player, destinations[0])

func _open_link_menu(player: Node):
	# Find all other captured sigils that aren't linked
	var available_sigils = []
	for sigil in get_tree().get_nodes_in_group("capture_sigil"):
		if can_link_to(sigil):
			available_sigils.append(sigil)

	if available_sigils.size() == 0:
		if has_node("/root/ChatSystem"):
			get_node("/root/ChatSystem").emit_system_message("No available sigils to link!")
		return

	# Show link selection UI or link to nearest
	var nearest_sigil = null
	var nearest_dist = INF
	for sigil in available_sigils:
		var dist = global_position.distance_to(sigil.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_sigil = sigil

	if nearest_sigil:
		link_to(nearest_sigil, player)

# ============================================
# UTILITY
# ============================================

func get_sigil_info() -> Dictionary:
	return {
		"id": sigil_id,
		"name": sigil_name,
		"state": current_state,
		"captured": current_state == SigilState.CAPTURED,
		"links": linked_sigils.size(),
		"position": global_position
	}

func reset_sigil():
	current_state = SigilState.NEUTRAL
	capture_progress = 0.0
	owning_team = -1

	# Break all links
	for sigil in linked_sigils.duplicate():
		unlink_from(sigil)

	teleport_cooldowns.clear()
	_update_visuals()
