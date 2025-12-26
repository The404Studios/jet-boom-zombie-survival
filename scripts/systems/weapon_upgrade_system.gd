extends Node
class_name WeaponUpgradeSystem

# Weapon upgrade system for enhancing weapons with various modifiers

signal weapon_upgraded(weapon: Resource, upgrade_type: UpgradeType)
signal upgrade_failed(reason: String)

enum UpgradeType {
	DAMAGE,
	FIRE_RATE,
	MAGAZINE_SIZE,
	RELOAD_SPEED,
	RANGE,
	ACCURACY,
	PENETRATION,
	ELEMENTAL_FIRE,
	ELEMENTAL_ICE,
	ELEMENTAL_ELECTRIC
}

# Upgrade costs in sigils
const UPGRADE_COSTS = {
	UpgradeType.DAMAGE: 100,
	UpgradeType.FIRE_RATE: 80,
	UpgradeType.MAGAZINE_SIZE: 60,
	UpgradeType.RELOAD_SPEED: 50,
	UpgradeType.RANGE: 40,
	UpgradeType.ACCURACY: 40,
	UpgradeType.PENETRATION: 150,
	UpgradeType.ELEMENTAL_FIRE: 200,
	UpgradeType.ELEMENTAL_ICE: 200,
	UpgradeType.ELEMENTAL_ELECTRIC: 250
}

# Maximum upgrade levels
const MAX_LEVELS = {
	UpgradeType.DAMAGE: 5,
	UpgradeType.FIRE_RATE: 5,
	UpgradeType.MAGAZINE_SIZE: 3,
	UpgradeType.RELOAD_SPEED: 3,
	UpgradeType.RANGE: 3,
	UpgradeType.ACCURACY: 3,
	UpgradeType.PENETRATION: 2,
	UpgradeType.ELEMENTAL_FIRE: 1,
	UpgradeType.ELEMENTAL_ICE: 1,
	UpgradeType.ELEMENTAL_ELECTRIC: 1
}

# Upgrade multipliers per level
const UPGRADE_VALUES = {
	UpgradeType.DAMAGE: 0.15,  # +15% per level
	UpgradeType.FIRE_RATE: 0.10,  # +10% faster per level
	UpgradeType.MAGAZINE_SIZE: 0.25,  # +25% capacity per level
	UpgradeType.RELOAD_SPEED: 0.15,  # 15% faster per level
	UpgradeType.RANGE: 0.20,  # +20% range per level
	UpgradeType.ACCURACY: 0.15,  # +15% accuracy per level
	UpgradeType.PENETRATION: 1.0,  # Can penetrate 1 target per level
	UpgradeType.ELEMENTAL_FIRE: 5.0,  # Burn damage per second
	UpgradeType.ELEMENTAL_ICE: 0.3,  # 30% slow effect
	UpgradeType.ELEMENTAL_ELECTRIC: 0.2  # 20% chain chance
}

# Track weapon upgrades: weapon_id -> {upgrade_type -> level}
var weapon_upgrades: Dictionary = {}

func _ready():
	add_to_group("weapon_upgrade_system")

func get_upgrade_cost(upgrade_type: UpgradeType, current_level: int) -> int:
	"""Get the cost for the next upgrade level"""
	var base_cost = UPGRADE_COSTS.get(upgrade_type, 100)
	# Cost increases by 50% per level
	return int(base_cost * pow(1.5, current_level))

func get_upgrade_level(weapon: Resource, upgrade_type: UpgradeType) -> int:
	"""Get current upgrade level for a weapon"""
	var weapon_id = _get_weapon_id(weapon)
	if weapon_id not in weapon_upgrades:
		return 0
	return weapon_upgrades[weapon_id].get(upgrade_type, 0)

func can_upgrade(weapon: Resource, upgrade_type: UpgradeType) -> bool:
	"""Check if weapon can be upgraded"""
	if not weapon:
		return false

	var current_level = get_upgrade_level(weapon, upgrade_type)
	var max_level = MAX_LEVELS.get(upgrade_type, 1)

	if current_level >= max_level:
		return false

	# Check for elemental conflicts
	if upgrade_type in [UpgradeType.ELEMENTAL_FIRE, UpgradeType.ELEMENTAL_ICE, UpgradeType.ELEMENTAL_ELECTRIC]:
		for elem in [UpgradeType.ELEMENTAL_FIRE, UpgradeType.ELEMENTAL_ICE, UpgradeType.ELEMENTAL_ELECTRIC]:
			if elem != upgrade_type and get_upgrade_level(weapon, elem) > 0:
				return false  # Can only have one elemental type

	return true

func upgrade_weapon(weapon: Resource, upgrade_type: UpgradeType, player: Node = null) -> bool:
	"""Apply an upgrade to a weapon"""
	if not can_upgrade(weapon, upgrade_type):
		upgrade_failed.emit("Maximum upgrade level reached")
		return false

	var current_level = get_upgrade_level(weapon, upgrade_type)
	var cost = get_upgrade_cost(upgrade_type, current_level)

	# Check if player can afford
	var sigil_shop = get_tree().get_first_node_in_group("sigil_shop")
	if not sigil_shop:
		sigil_shop = get_node_or_null("/root/SigilShop")

	if sigil_shop:
		if "current_sigils" in sigil_shop and sigil_shop.current_sigils < cost:
			upgrade_failed.emit("Not enough sigils! Need %d" % cost)
			return false

		# Spend sigils
		if sigil_shop.has_method("spend_sigils"):
			sigil_shop.spend_sigils(cost)
		else:
			sigil_shop.current_sigils -= cost

	# Apply upgrade
	var weapon_id = _get_weapon_id(weapon)
	if weapon_id not in weapon_upgrades:
		weapon_upgrades[weapon_id] = {}

	weapon_upgrades[weapon_id][upgrade_type] = current_level + 1

	# Notify
	weapon_upgraded.emit(weapon, upgrade_type)

	if has_node("/root/ChatSystem"):
		var upgrade_name = _get_upgrade_name(upgrade_type)
		var weapon_name = weapon.item_name if "item_name" in weapon else "Weapon"
		get_node("/root/ChatSystem").emit_system_message(
			"%s upgraded with %s (Level %d)" % [weapon_name, upgrade_name, current_level + 1]
		)

	return true

func get_modified_damage(weapon: Resource, base_damage: float) -> float:
	"""Get damage modified by upgrades"""
	var level = get_upgrade_level(weapon, UpgradeType.DAMAGE)
	var multiplier = 1.0 + (level * UPGRADE_VALUES[UpgradeType.DAMAGE])
	return base_damage * multiplier

func get_modified_fire_rate(weapon: Resource, base_rate: float) -> float:
	"""Get fire rate modified by upgrades (lower is faster)"""
	var level = get_upgrade_level(weapon, UpgradeType.FIRE_RATE)
	var multiplier = 1.0 - (level * UPGRADE_VALUES[UpgradeType.FIRE_RATE])
	return base_rate * max(multiplier, 0.2)  # Cap at 80% reduction

func get_modified_magazine_size(weapon: Resource, base_size: int) -> int:
	"""Get magazine size modified by upgrades"""
	var level = get_upgrade_level(weapon, UpgradeType.MAGAZINE_SIZE)
	var multiplier = 1.0 + (level * UPGRADE_VALUES[UpgradeType.MAGAZINE_SIZE])
	return int(base_size * multiplier)

func get_modified_reload_time(weapon: Resource, base_time: float) -> float:
	"""Get reload time modified by upgrades"""
	var level = get_upgrade_level(weapon, UpgradeType.RELOAD_SPEED)
	var multiplier = 1.0 - (level * UPGRADE_VALUES[UpgradeType.RELOAD_SPEED])
	return base_time * max(multiplier, 0.3)

func get_modified_range(weapon: Resource, base_range: float) -> float:
	"""Get range modified by upgrades"""
	var level = get_upgrade_level(weapon, UpgradeType.RANGE)
	var multiplier = 1.0 + (level * UPGRADE_VALUES[UpgradeType.RANGE])
	return base_range * multiplier

func get_penetration_count(weapon: Resource) -> int:
	"""Get number of targets bullet can penetrate"""
	return get_upgrade_level(weapon, UpgradeType.PENETRATION)

func get_elemental_type(weapon: Resource) -> UpgradeType:
	"""Get the elemental upgrade type on this weapon, or -1 if none"""
	if get_upgrade_level(weapon, UpgradeType.ELEMENTAL_FIRE) > 0:
		return UpgradeType.ELEMENTAL_FIRE
	if get_upgrade_level(weapon, UpgradeType.ELEMENTAL_ICE) > 0:
		return UpgradeType.ELEMENTAL_ICE
	if get_upgrade_level(weapon, UpgradeType.ELEMENTAL_ELECTRIC) > 0:
		return UpgradeType.ELEMENTAL_ELECTRIC
	return -1

func apply_elemental_effect(weapon: Resource, target: Node, hit_position: Vector3):
	"""Apply elemental effects to a target"""
	var elem_type = get_elemental_type(weapon)

	match elem_type:
		UpgradeType.ELEMENTAL_FIRE:
			_apply_fire_effect(target, hit_position)
		UpgradeType.ELEMENTAL_ICE:
			_apply_ice_effect(target)
		UpgradeType.ELEMENTAL_ELECTRIC:
			_apply_electric_effect(target, hit_position)

func _apply_fire_effect(target: Node, hit_position: Vector3):
	"""Apply burning damage over time"""
	if target.has_method("apply_burn"):
		target.apply_burn(UPGRADE_VALUES[UpgradeType.ELEMENTAL_FIRE])
	elif target.has_method("take_damage"):
		# Create burn timer
		var burn_damage = UPGRADE_VALUES[UpgradeType.ELEMENTAL_FIRE]
		var burn_duration = 3.0
		var burn_timer = 0.0

		# Spawn fire particles
		_spawn_fire_particles(hit_position)

func _apply_ice_effect(target: Node):
	"""Apply slow effect"""
	if target.has_method("apply_slow"):
		target.apply_slow(UPGRADE_VALUES[UpgradeType.ELEMENTAL_ICE], 2.0)
	elif "move_speed" in target:
		var original_speed = target.move_speed
		target.move_speed *= (1.0 - UPGRADE_VALUES[UpgradeType.ELEMENTAL_ICE])

		# Reset after duration
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(target):
				target.move_speed = original_speed
		)

func _apply_electric_effect(target: Node, hit_position: Vector3):
	"""Chain lightning to nearby enemies"""
	var chain_chance = UPGRADE_VALUES[UpgradeType.ELEMENTAL_ELECTRIC]
	if randf() > chain_chance:
		return

	# Find nearby enemies
	var nearby = get_tree().get_nodes_in_group("zombie")
	var chain_targets = []
	var chain_range = 5.0

	for enemy in nearby:
		if enemy == target:
			continue
		if not is_instance_valid(enemy):
			continue
		var dist = target.global_position.distance_to(enemy.global_position)
		if dist <= chain_range:
			chain_targets.append(enemy)
			if chain_targets.size() >= 2:
				break

	# Apply chain damage
	for chain_target in chain_targets:
		if chain_target.has_method("take_damage"):
			chain_target.take_damage(10.0, chain_target.global_position)

		# Spawn lightning effect
		_spawn_lightning_effect(target.global_position, chain_target.global_position)

func _spawn_fire_particles(pos: Vector3):
	var particles = GPUParticles3D.new()
	particles.global_position = pos
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 15
	particles.lifetime = 0.5

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.2
	material.direction = Vector3(0, 1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0
	material.gravity = Vector3(0, 2, 0)
	material.color = Color(1.0, 0.5, 0.1)
	particles.process_material = material

	get_tree().current_scene.add_child(particles)

	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func _spawn_lightning_effect(from: Vector3, to: Vector3):
	var line = MeshInstance3D.new()
	var immediate_mesh = ImmediateMesh.new()

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var segments = 5
	var direction = to - from

	for i in range(segments + 1):
		var t = float(i) / segments
		var point = from.lerp(to, t)
		if i > 0 and i < segments:
			point += Vector3(
				randf_range(-0.2, 0.2),
				randf_range(-0.2, 0.2),
				randf_range(-0.2, 0.2)
			)
		immediate_mesh.surface_add_vertex(point)

	immediate_mesh.surface_end()
	line.mesh = immediate_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.7, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.6, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = mat

	get_tree().current_scene.add_child(line)

	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(line):
		line.queue_free()

func _get_weapon_id(weapon: Resource) -> String:
	"""Get unique ID for a weapon"""
	if weapon.has_method("get_instance_id"):
		return str(weapon.get_instance_id())
	if "item_name" in weapon:
		return weapon.item_name
	return str(weapon.get_rid())

func _get_upgrade_name(upgrade_type: UpgradeType) -> String:
	match upgrade_type:
		UpgradeType.DAMAGE:
			return "Damage Boost"
		UpgradeType.FIRE_RATE:
			return "Rapid Fire"
		UpgradeType.MAGAZINE_SIZE:
			return "Extended Magazine"
		UpgradeType.RELOAD_SPEED:
			return "Quick Reload"
		UpgradeType.RANGE:
			return "Extended Range"
		UpgradeType.ACCURACY:
			return "Precision"
		UpgradeType.PENETRATION:
			return "Armor Piercing"
		UpgradeType.ELEMENTAL_FIRE:
			return "Incendiary Rounds"
		UpgradeType.ELEMENTAL_ICE:
			return "Cryo Rounds"
		UpgradeType.ELEMENTAL_ELECTRIC:
			return "Tesla Rounds"
	return "Unknown"

func get_all_upgrades(weapon: Resource) -> Dictionary:
	"""Get all upgrades for a weapon"""
	var weapon_id = _get_weapon_id(weapon)
	if weapon_id in weapon_upgrades:
		return weapon_upgrades[weapon_id].duplicate()
	return {}

func get_available_upgrades(weapon: Resource) -> Array:
	"""Get list of available upgrade types for a weapon"""
	var available = []
	for upgrade_type in UpgradeType.values():
		if can_upgrade(weapon, upgrade_type):
			available.append({
				"type": upgrade_type,
				"name": _get_upgrade_name(upgrade_type),
				"current_level": get_upgrade_level(weapon, upgrade_type),
				"max_level": MAX_LEVELS.get(upgrade_type, 1),
				"cost": get_upgrade_cost(upgrade_type, get_upgrade_level(weapon, upgrade_type))
			})
	return available

func reset_weapon_upgrades(weapon: Resource):
	"""Remove all upgrades from a weapon (for respec)"""
	var weapon_id = _get_weapon_id(weapon)
	if weapon_id in weapon_upgrades:
		weapon_upgrades.erase(weapon_id)

func save_upgrades() -> Dictionary:
	"""Get upgrade data for saving"""
	return weapon_upgrades.duplicate(true)

func load_upgrades(data: Dictionary):
	"""Load upgrade data from save"""
	weapon_upgrades = data.duplicate(true)
