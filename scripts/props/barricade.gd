extends StaticBody3D
class_name Barricade

## Base barricade/prop class with HP, repair, and network sync
## Zombies will target these before players

signal health_changed(current: float, max_hp: float)
signal damaged(amount: float, attacker: Node)
signal destroyed
signal repaired(amount: float)
signal phase_state_changed(is_phased: bool)

enum BarricadeType {
	DOORWAY,
	WALL,
	WINDOW_BOARD,
	WIRE_FENCE,
	SANDBAG,
	METAL_SHEET,
	WOODEN_PLANK,
	HALLWAY_BLOCK,
	FLOOR_TRAP,
	SIGIL
}

enum BarricadeState {
	INTACT,
	DAMAGED,
	CRITICAL,
	DESTROYED
}

@export var barricade_type: BarricadeType = BarricadeType.WOODEN_PLANK
@export var max_health: float = 100.0
@export var repair_rate: float = 10.0  # HP per second when repairing
@export var can_be_nailed: bool = true
@export var is_nailed: bool = false
@export var nail_strength_bonus: float = 1.5  # HP multiplier when nailed
@export var priority_weight: float = 1.0  # Higher = zombies prefer this target

# Placement
@export var placement_cost: int = 100
@export var can_be_picked_up: bool = true
@export var snap_to_grid: bool = true
@export var grid_size: float = 1.0

# Network
@export var owner_peer_id: int = 0
var network_id: int = 0
static var _next_network_id: int = 1

# State
var current_health: float = 100.0
var state: BarricadeState = BarricadeState.INTACT
var is_being_repaired: bool = false
var repairer_peer_id: int = 0
var is_phased: bool = false  # When players can pass through
var phasing_players: Array[int] = []  # Peer IDs of players currently phasing

# Components
@onready var collision_shape: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var health_bar_3d: Node3D = $HealthBar3D if has_node("HealthBar3D") else null
@onready var damage_particles: GPUParticles3D = $DamageParticles if has_node("DamageParticles") else null
@onready var repair_particles: GPUParticles3D = $RepairParticles if has_node("RepairParticles") else null
@onready var audio_player: AudioStreamPlayer3D = $AudioPlayer if has_node("AudioPlayer") else null

# Visual state
var original_material: Material = null
var damage_overlay_material: Material = null

# Repair interaction
var repair_progress: float = 0.0
const REPAIR_HOLD_TIME: float = 0.5  # Seconds to hold before repair starts

func _ready():
	# Generate network ID
	network_id = _next_network_id
	_next_network_id += 1

	# Initialize health
	current_health = max_health
	if is_nailed:
		current_health *= nail_strength_bonus
		max_health *= nail_strength_bonus

	# Setup collision
	_setup_collision()

	# Store original material
	if mesh_instance and mesh_instance.get_surface_override_material(0):
		original_material = mesh_instance.get_surface_override_material(0).duplicate()

	# Add to groups
	add_to_group("barricades")
	add_to_group("zombie_targets")
	add_to_group("props")

	# Create health bar if not exists
	if not health_bar_3d:
		_create_health_bar()

	_update_visual_state()

func _physics_process(delta):
	# Handle repair progress
	if is_being_repaired and current_health < max_health:
		var repair_amount = repair_rate * delta
		heal(repair_amount)

	# Update health bar visibility based on camera distance
	_update_health_bar_visibility()

func _setup_collision():
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		add_child(collision_shape)

	# Set collision layers
	# Layer 1: World
	# Layer 2: Players
	# Layer 3: Zombies
	# Layer 4: Props/Barricades
	collision_layer = 1 | 8  # World + Props layer
	collision_mask = 1 | 2 | 4  # World + Players + Zombies

func _create_health_bar():
	health_bar_3d = Node3D.new()
	health_bar_3d.name = "HealthBar3D"

	# Create background bar
	var bg_mesh = MeshInstance3D.new()
	bg_mesh.name = "Background"
	var bg_quad = QuadMesh.new()
	bg_quad.size = Vector2(1.0, 0.1)
	bg_mesh.mesh = bg_quad

	var bg_material = StandardMaterial3D.new()
	bg_material.albedo_color = Color(0.2, 0.2, 0.2, 0.8)
	bg_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mesh.set_surface_override_material(0, bg_material)
	health_bar_3d.add_child(bg_mesh)

	# Create fill bar
	var fill_mesh = MeshInstance3D.new()
	fill_mesh.name = "Fill"
	var fill_quad = QuadMesh.new()
	fill_quad.size = Vector2(0.98, 0.08)
	fill_mesh.mesh = fill_quad
	fill_mesh.position.z = 0.01

	var fill_material = StandardMaterial3D.new()
	fill_material.albedo_color = Color.GREEN
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mesh.set_surface_override_material(0, fill_material)
	health_bar_3d.add_child(fill_mesh)

	# Position above barricade
	health_bar_3d.position.y = 1.5
	health_bar_3d.visible = false  # Hidden until damaged
	add_child(health_bar_3d)

func _update_health_bar_visibility():
	if not health_bar_3d:
		return

	# Show health bar only when damaged
	health_bar_3d.visible = current_health < max_health and state != BarricadeState.DESTROYED

	if health_bar_3d.visible:
		# Face camera
		var camera = get_viewport().get_camera_3d()
		if camera:
			health_bar_3d.look_at(camera.global_position, Vector3.UP)

		# Update fill
		var fill = health_bar_3d.get_node_or_null("Fill")
		if fill:
			var health_percent = current_health / max_health
			fill.scale.x = health_percent

			# Color based on health
			var fill_mat = fill.get_surface_override_material(0) as StandardMaterial3D
			if fill_mat:
				if health_percent > 0.6:
					fill_mat.albedo_color = Color.GREEN
				elif health_percent > 0.3:
					fill_mat.albedo_color = Color.YELLOW
				else:
					fill_mat.albedo_color = Color.RED

# ============================================
# DAMAGE AND HEALING
# ============================================

func take_damage(amount: float, attacker: Node = null) -> bool:
	if state == BarricadeState.DESTROYED:
		return false

	var actual_damage = amount
	if is_nailed:
		actual_damage *= 0.7  # Nailed props take less damage

	current_health = max(0, current_health - actual_damage)

	_update_state()
	_update_visual_state()

	health_changed.emit(current_health, max_health)
	damaged.emit(actual_damage, attacker)

	# Play damage effects
	if damage_particles:
		damage_particles.emitting = true

	if audio_player:
		_play_damage_sound()

	# Sync over network
	if multiplayer.is_server():
		_sync_damage.rpc(actual_damage, current_health)

	if current_health <= 0:
		_on_destroyed()
		return true

	return false

func heal(amount: float):
	if state == BarricadeState.DESTROYED:
		return

	var old_health = current_health
	current_health = min(max_health, current_health + amount)

	if current_health != old_health:
		_update_state()
		_update_visual_state()

		health_changed.emit(current_health, max_health)
		repaired.emit(current_health - old_health)

		if repair_particles and not repair_particles.emitting:
			repair_particles.emitting = true

		# Sync over network
		if multiplayer.is_server():
			_sync_health.rpc(current_health)

func _update_state():
	var health_percent = current_health / max_health

	if current_health <= 0:
		state = BarricadeState.DESTROYED
	elif health_percent < 0.25:
		state = BarricadeState.CRITICAL
	elif health_percent < 0.6:
		state = BarricadeState.DAMAGED
	else:
		state = BarricadeState.INTACT

func _update_visual_state():
	if not mesh_instance:
		return

	var health_percent = current_health / max_health

	# Tint based on damage
	var mat = mesh_instance.get_surface_override_material(0)
	if not mat and original_material:
		mat = original_material.duplicate()
		mesh_instance.set_surface_override_material(0, mat)

	if mat is StandardMaterial3D:
		if health_percent > 0.6:
			mat.albedo_color = Color.WHITE
		elif health_percent > 0.3:
			mat.albedo_color = Color(1.0, 0.9, 0.7)  # Slight yellow tint
		else:
			mat.albedo_color = Color(1.0, 0.6, 0.6)  # Red tint for critical

func _on_destroyed():
	state = BarricadeState.DESTROYED

	# Disable collision
	if collision_shape:
		collision_shape.disabled = true

	# Play destruction effects
	if damage_particles:
		damage_particles.amount = 50
		damage_particles.emitting = true

	if audio_player:
		_play_destroy_sound()

	# Hide mesh or play destruction animation
	if mesh_instance:
		var tween = create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3.ZERO, 0.3)
		tween.tween_callback(queue_free)

	destroyed.emit()

	# Sync over network
	if multiplayer.is_server():
		_sync_destroyed.rpc()

func _play_damage_sound():
	# Would load appropriate sound based on barricade type
	pass

func _play_destroy_sound():
	# Would load destruction sound
	pass

# ============================================
# REPAIR SYSTEM
# ============================================

func start_repair(peer_id: int):
	if state == BarricadeState.DESTROYED or current_health >= max_health:
		return

	is_being_repaired = true
	repairer_peer_id = peer_id

	if multiplayer.is_server():
		_sync_repair_state.rpc(true, peer_id)

func stop_repair():
	is_being_repaired = false
	repairer_peer_id = 0

	if repair_particles:
		repair_particles.emitting = false

	if multiplayer.is_server():
		_sync_repair_state.rpc(false, 0)

func can_repair() -> bool:
	return state != BarricadeState.DESTROYED and current_health < max_health

# ============================================
# PHASE THROUGH SYSTEM
# ============================================

func set_phased_for_player(peer_id: int, phased: bool):
	"""Allow a specific player to phase through this barricade"""
	if phased:
		if peer_id not in phasing_players:
			phasing_players.append(peer_id)
	else:
		phasing_players.erase(peer_id)

	_update_phase_collision()

	if multiplayer.is_server():
		_sync_phase_state.rpc(phasing_players)

func is_player_phasing(peer_id: int) -> bool:
	return peer_id in phasing_players

func _update_phase_collision():
	# This is handled per-player in the player controller
	# The barricade tracks who is phasing for network sync
	pass

# ============================================
# NAILING SYSTEM
# ============================================

func nail_to_surface():
	"""Nail this barricade to a surface for extra durability"""
	if not can_be_nailed or is_nailed:
		return false

	is_nailed = true
	can_be_picked_up = false

	# Increase max health
	var health_ratio = current_health / max_health
	max_health *= nail_strength_bonus
	current_health = max_health * health_ratio

	health_changed.emit(current_health, max_health)

	if multiplayer.is_server():
		_sync_nailed.rpc(true)

	return true

func remove_nails():
	"""Remove nails (takes time, handled by player)"""
	if not is_nailed:
		return false

	is_nailed = false
	can_be_picked_up = true

	# Reduce max health
	var health_ratio = current_health / max_health
	max_health /= nail_strength_bonus
	current_health = max_health * health_ratio

	health_changed.emit(current_health, max_health)

	if multiplayer.is_server():
		_sync_nailed.rpc(false)

	return true

# ============================================
# NETWORK SYNC
# ============================================

@rpc("authority", "call_remote", "reliable")
func _sync_damage(_amount: float, new_health: float):
	current_health = new_health
	_update_state()
	_update_visual_state()
	health_changed.emit(current_health, max_health)

@rpc("authority", "call_remote", "reliable")
func _sync_health(new_health: float):
	current_health = new_health
	_update_state()
	_update_visual_state()
	health_changed.emit(current_health, max_health)

@rpc("authority", "call_remote", "reliable")
func _sync_destroyed():
	_on_destroyed()

@rpc("authority", "call_remote", "reliable")
func _sync_repair_state(repairing: bool, peer_id: int):
	is_being_repaired = repairing
	repairer_peer_id = peer_id

	if repair_particles:
		repair_particles.emitting = repairing

@rpc("authority", "call_remote", "reliable")
func _sync_phase_state(players: Array):
	phasing_players.clear()
	for p in players:
		phasing_players.append(p)

@rpc("authority", "call_remote", "reliable")
func _sync_nailed(nailed: bool):
	is_nailed = nailed
	can_be_picked_up = not nailed

# ============================================
# UTILITY
# ============================================

func get_health_percent() -> float:
	return current_health / max_health if max_health > 0 else 0.0

func get_state_name() -> String:
	match state:
		BarricadeState.INTACT: return "Intact"
		BarricadeState.DAMAGED: return "Damaged"
		BarricadeState.CRITICAL: return "Critical"
		BarricadeState.DESTROYED: return "Destroyed"
	return "Unknown"

func get_type_name() -> String:
	match barricade_type:
		BarricadeType.DOORWAY: return "Doorway"
		BarricadeType.WALL: return "Wall"
		BarricadeType.WINDOW_BOARD: return "Window Board"
		BarricadeType.WIRE_FENCE: return "Wire Fence"
		BarricadeType.SANDBAG: return "Sandbag"
		BarricadeType.METAL_SHEET: return "Metal Sheet"
		BarricadeType.WOODEN_PLANK: return "Wooden Plank"
		BarricadeType.HALLWAY_BLOCK: return "Hallway Block"
		BarricadeType.FLOOR_TRAP: return "Floor Trap"
		BarricadeType.SIGIL: return "Sigil"
	return "Unknown"

func to_network_data() -> Dictionary:
	return {
		"network_id": network_id,
		"type": barricade_type,
		"position": global_position,
		"rotation": global_rotation,
		"health": current_health,
		"max_health": max_health,
		"is_nailed": is_nailed,
		"owner_peer_id": owner_peer_id,
		"phasing_players": phasing_players
	}

static func from_network_data(data: Dictionary, scene: PackedScene) -> Barricade:
	var barricade = scene.instantiate() as Barricade
	if barricade:
		barricade.network_id = data.get("network_id", 0)
		barricade.barricade_type = data.get("type", BarricadeType.WOODEN_PLANK)
		barricade.global_position = data.get("position", Vector3.ZERO)
		barricade.global_rotation = data.get("rotation", Vector3.ZERO)
		barricade.current_health = data.get("health", 100.0)
		barricade.max_health = data.get("max_health", 100.0)
		barricade.is_nailed = data.get("is_nailed", false)
		barricade.owner_peer_id = data.get("owner_peer_id", 0)
	return barricade
