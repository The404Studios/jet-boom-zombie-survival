extends Node

## Wave progression and loot drop system
## Handles difficulty scaling and zombie loot tables

signal wave_difficulty_changed(wave: int, multiplier: float)
signal loot_dropped(position: Vector3, items: Array)
signal boss_spawned(boss_type: String, wave: int)

# Wave configuration
const BASE_ZOMBIE_COUNT: int = 10
const ZOMBIE_COUNT_MULTIPLIER: float = 1.15
const BASE_ZOMBIE_HEALTH: float = 100.0
const HEALTH_MULTIPLIER_PER_WAVE: float = 1.08
const BASE_ZOMBIE_DAMAGE: float = 15.0
const DAMAGE_MULTIPLIER_PER_WAVE: float = 1.05
const BASE_ZOMBIE_SPEED: float = 3.0
const SPEED_MULTIPLIER_PER_WAVE: float = 1.02

# Special wave thresholds
const BOSS_WAVES: Array = [5, 10, 15, 20, 25, 30]
const ELITE_SPAWN_START_WAVE: int = 3
const SPECIAL_SPAWN_START_WAVE: int = 7
const NIGHTMARE_MODE_WAVE: int = 30

# Loot configuration
const BASE_DROP_CHANCE: float = 0.3
const ELITE_DROP_MULTIPLIER: float = 2.0
const BOSS_GUARANTEED_DROPS: int = 3
const NIGHTMARE_RARITY_BOOST: int = 1

# Zombie types
enum ZombieType {
	NORMAL,
	FAST,
	TANK,
	SPITTER,
	EXPLODER,
	ELITE,
	BOSS_BRUTE,
	BOSS_HIVEMIND,
	BOSS_ABOMINATION
}

# Loot tables by zombie type
var loot_tables: Dictionary = {
	ZombieType.NORMAL: {
		"common": ["bandage", "pistol_ammo", "scrap_metal", "cloth"],
		"uncommon": ["medkit_small", "rifle_ammo", "repair_kit"],
		"rare": ["stimulant", "grenade"],
		"weights": [70, 25, 5, 0, 0]
	},
	ZombieType.FAST: {
		"common": ["bandage", "energy_drink", "pistol_ammo"],
		"uncommon": ["adrenaline_shot", "smg_ammo"],
		"rare": ["speed_boost", "combat_knife"],
		"weights": [60, 30, 10, 0, 0]
	},
	ZombieType.TANK: {
		"common": ["scrap_metal", "armor_plate_damaged", "shotgun_ammo"],
		"uncommon": ["armor_plate", "repair_kit", "heavy_ammo"],
		"rare": ["reinforced_plate", "tactical_vest"],
		"epic": ["heavy_armor_piece"],
		"weights": [50, 35, 12, 3, 0]
	},
	ZombieType.SPITTER: {
		"common": ["acid_sample", "cloth", "chemical_compound"],
		"uncommon": ["acid_grenade", "hazmat_piece", "antidote"],
		"rare": ["corrosive_rounds", "gas_mask"],
		"weights": [55, 35, 10, 0, 0]
	},
	ZombieType.EXPLODER: {
		"common": ["explosive_residue", "fuse", "gunpowder"],
		"uncommon": ["grenade", "c4_charge", "explosive_ammo"],
		"rare": ["rocket_ammo", "proximity_mine"],
		"epic": ["grenade_launcher_ammo"],
		"weights": [45, 40, 12, 3, 0]
	},
	ZombieType.ELITE: {
		"common": ["medkit_small", "rifle_ammo", "armor_plate"],
		"uncommon": ["medkit_large", "special_ammo", "military_vest"],
		"rare": ["rare_weapon_part", "night_vision", "advanced_medkit"],
		"epic": ["elite_weapon_mod", "exo_frame_piece"],
		"weights": [30, 40, 25, 5, 0]
	},
	ZombieType.BOSS_BRUTE: {
		"uncommon": ["heavy_armor_plate", "minigun_ammo", "large_medkit"],
		"rare": ["brute_trophy", "heavy_weapon_part", "reinforced_exo"],
		"epic": ["legendary_armor_piece", "heavy_weapon_blueprint"],
		"legendary": ["brute_slayer_title", "boss_essence"],
		"weights": [0, 30, 45, 20, 5]
	},
	ZombieType.BOSS_HIVEMIND: {
		"uncommon": ["psionic_residue", "neural_implant", "mind_shield"],
		"rare": ["hivemind_core", "psychic_amplifier", "control_chip"],
		"epic": ["mind_control_device", "neural_network_piece"],
		"legendary": ["hivemind_crown", "boss_essence"],
		"weights": [0, 25, 45, 25, 5]
	},
	ZombieType.BOSS_ABOMINATION: {
		"uncommon": ["mutagen_sample", "bio_weapon_part", "regenerative_tissue"],
		"rare": ["abomination_heart", "mutation_serum", "bio_armor"],
		"epic": ["genetic_modifier", "living_weapon_piece"],
		"legendary": ["abomination_core", "boss_essence"],
		"weights": [0, 20, 45, 28, 7]
	}
}

# Current wave state
var current_wave: int = 0
var is_nightmare_mode: bool = false
var total_zombies_killed: int = 0
var current_wave_zombies_remaining: int = 0

# Cached calculations
var cached_difficulty: Dictionary = {}

func _ready():
	_precalculate_difficulties()

func _precalculate_difficulties():
	for wave in range(1, 51):
		cached_difficulty[wave] = _calculate_wave_difficulty(wave)

func _calculate_wave_difficulty(wave: int) -> Dictionary:
	var nightmare_mult = 1.5 if wave > NIGHTMARE_MODE_WAVE else 1.0
	
	return {
		"zombie_count": int(BASE_ZOMBIE_COUNT * pow(ZOMBIE_COUNT_MULTIPLIER, wave - 1) * nightmare_mult),
		"health_multiplier": pow(HEALTH_MULTIPLIER_PER_WAVE, wave - 1) * nightmare_mult,
		"damage_multiplier": pow(DAMAGE_MULTIPLIER_PER_WAVE, wave - 1) * nightmare_mult,
		"speed_multiplier": min(pow(SPEED_MULTIPLIER_PER_WAVE, wave - 1), 2.0),
		"elite_chance": _get_elite_spawn_chance(wave),
		"special_types": _get_available_special_types(wave),
		"is_boss_wave": wave in BOSS_WAVES,
		"boss_type": _get_boss_type(wave) if wave in BOSS_WAVES else ZombieType.NORMAL
	}

func _get_elite_spawn_chance(wave: int) -> float:
	if wave < ELITE_SPAWN_START_WAVE:
		return 0.0
	var base_chance = 0.05
	var wave_bonus = (wave - ELITE_SPAWN_START_WAVE) * 0.02
	return min(base_chance + wave_bonus, 0.25)

func _get_available_special_types(wave: int) -> Array:
	var types = [ZombieType.NORMAL]
	
	if wave >= 2:
		types.append(ZombieType.FAST)
	if wave >= 4:
		types.append(ZombieType.TANK)
	if wave >= SPECIAL_SPAWN_START_WAVE:
		types.append(ZombieType.SPITTER)
	if wave >= 10:
		types.append(ZombieType.EXPLODER)
	
	return types

func _get_boss_type(wave: int) -> int:
	match wave:
		5, 20:
			return ZombieType.BOSS_BRUTE
		10, 25:
			return ZombieType.BOSS_HIVEMIND
		15, 30:
			return ZombieType.BOSS_ABOMINATION
		_:
			return ZombieType.BOSS_BRUTE

# ============================================
# WAVE MANAGEMENT
# ============================================

func start_wave(wave_number: int) -> Dictionary:
	current_wave = wave_number
	is_nightmare_mode = wave_number > NIGHTMARE_MODE_WAVE
	
	var difficulty = get_wave_difficulty(wave_number)
	current_wave_zombies_remaining = difficulty.zombie_count
	
	wave_difficulty_changed.emit(wave_number, difficulty.health_multiplier)
	
	return difficulty

func get_wave_difficulty(wave: int) -> Dictionary:
	if wave in cached_difficulty:
		return cached_difficulty[wave]
	return _calculate_wave_difficulty(wave)

func get_spawn_configuration(wave: int) -> Array:
	var difficulty = get_wave_difficulty(wave)
	var spawn_list = []
	var total_count = difficulty.zombie_count
	
	# Boss wave handling
	if difficulty.is_boss_wave:
		spawn_list.append({
			"type": difficulty.boss_type,
			"count": 1,
			"health": BASE_ZOMBIE_HEALTH * difficulty.health_multiplier * 10.0,
			"damage": BASE_ZOMBIE_DAMAGE * difficulty.damage_multiplier * 2.0,
			"speed": BASE_ZOMBIE_SPEED * 0.7
		})
		total_count -= 1
		boss_spawned.emit(_get_boss_name(difficulty.boss_type), wave)
	
	# Elite spawns
	var elite_count = int(total_count * difficulty.elite_chance)
	if elite_count > 0:
		spawn_list.append({
			"type": ZombieType.ELITE,
			"count": elite_count,
			"health": BASE_ZOMBIE_HEALTH * difficulty.health_multiplier * 2.5,
			"damage": BASE_ZOMBIE_DAMAGE * difficulty.damage_multiplier * 1.5,
			"speed": BASE_ZOMBIE_SPEED * difficulty.speed_multiplier * 1.1
		})
		total_count -= elite_count
	
	# Distribute remaining among available types
	var special_types = difficulty.special_types
	var type_weights = _get_type_weights(wave)
	
	for zombie_type in special_types:
		var weight = type_weights.get(zombie_type, 0)
		var count = int(total_count * weight)
		if count > 0:
			var stats = _get_zombie_base_stats(zombie_type)
			spawn_list.append({
				"type": zombie_type,
				"count": count,
				"health": stats.health * difficulty.health_multiplier,
				"damage": stats.damage * difficulty.damage_multiplier,
				"speed": stats.speed * difficulty.speed_multiplier
			})
	
	return spawn_list

func _get_type_weights(wave: int) -> Dictionary:
	var weights = {
		ZombieType.NORMAL: 0.6,
		ZombieType.FAST: 0.0,
		ZombieType.TANK: 0.0,
		ZombieType.SPITTER: 0.0,
		ZombieType.EXPLODER: 0.0
	}
	
	if wave >= 2:
		weights[ZombieType.NORMAL] -= 0.15
		weights[ZombieType.FAST] = 0.15
	if wave >= 4:
		weights[ZombieType.NORMAL] -= 0.1
		weights[ZombieType.TANK] = 0.1
	if wave >= SPECIAL_SPAWN_START_WAVE:
		weights[ZombieType.NORMAL] -= 0.1
		weights[ZombieType.SPITTER] = 0.1
	if wave >= 10:
		weights[ZombieType.NORMAL] -= 0.1
		weights[ZombieType.EXPLODER] = 0.1
	
	# Nightmare mode increases special spawns
	if wave > NIGHTMARE_MODE_WAVE:
		weights[ZombieType.NORMAL] = max(0.2, weights[ZombieType.NORMAL] - 0.2)
		weights[ZombieType.FAST] += 0.05
		weights[ZombieType.TANK] += 0.05
		weights[ZombieType.SPITTER] += 0.05
		weights[ZombieType.EXPLODER] += 0.05
	
	return weights

func _get_zombie_base_stats(zombie_type: int) -> Dictionary:
	match zombie_type:
		ZombieType.FAST:
			return {"health": 60.0, "damage": 10.0, "speed": 5.0}
		ZombieType.TANK:
			return {"health": 300.0, "damage": 25.0, "speed": 2.0}
		ZombieType.SPITTER:
			return {"health": 80.0, "damage": 20.0, "speed": 3.0}
		ZombieType.EXPLODER:
			return {"health": 50.0, "damage": 50.0, "speed": 3.5}
		_:
			return {"health": BASE_ZOMBIE_HEALTH, "damage": BASE_ZOMBIE_DAMAGE, "speed": BASE_ZOMBIE_SPEED}

func _get_boss_name(boss_type: int) -> String:
	match boss_type:
		ZombieType.BOSS_BRUTE:
			return "The Brute"
		ZombieType.BOSS_HIVEMIND:
			return "Hivemind Controller"
		ZombieType.BOSS_ABOMINATION:
			return "The Abomination"
		_:
			return "Unknown Boss"

# ============================================
# LOOT SYSTEM
# ============================================

func on_zombie_killed(zombie_type: int, position: Vector3, wave: int) -> Array:
	total_zombies_killed += 1
	current_wave_zombies_remaining -= 1
	
	var dropped_items = _generate_loot(zombie_type, wave)
	
	if dropped_items.size() > 0:
		loot_dropped.emit(position, dropped_items)
	
	return dropped_items

func _generate_loot(zombie_type: int, wave: int) -> Array:
	var items = []
	var loot_table = loot_tables.get(zombie_type, loot_tables[ZombieType.NORMAL])
	
	# Calculate drop chance
	var drop_chance = BASE_DROP_CHANCE
	if zombie_type == ZombieType.ELITE:
		drop_chance *= ELITE_DROP_MULTIPLIER
	
	# Boss guaranteed drops
	var guaranteed_drops = 0
	if zombie_type in [ZombieType.BOSS_BRUTE, ZombieType.BOSS_HIVEMIND, ZombieType.BOSS_ABOMINATION]:
		guaranteed_drops = BOSS_GUARANTEED_DROPS
		if wave > NIGHTMARE_MODE_WAVE:
			guaranteed_drops += 2
	
	# Generate drops
	var drop_count = guaranteed_drops
	if randf() < drop_chance:
		drop_count += 1
	if wave > NIGHTMARE_MODE_WAVE and randf() < 0.3:
		drop_count += 1
	
	for i in range(drop_count):
		var item = _roll_loot_item(loot_table, wave)
		if item:
			items.append(item)
	
	return items

func _roll_loot_item(loot_table: Dictionary, wave: int) -> Dictionary:
	var weights = loot_table.get("weights", [70, 25, 5, 0, 0])
	var rarity_names = ["common", "uncommon", "rare", "epic", "legendary"]
	
	# Nightmare mode boosts rarity
	if wave > NIGHTMARE_MODE_WAVE:
		weights = weights.duplicate()
		for i in range(weights.size() - 1):
			var shift = weights[i] * 0.15
			weights[i] -= shift
			if i + 1 < weights.size():
				weights[i + 1] += shift
	
	# Roll for rarity
	var roll = randf() * 100.0
	var cumulative = 0.0
	var selected_rarity = "common"
	
	for i in range(weights.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			selected_rarity = rarity_names[i]
			break
	
	# Get item from rarity pool
	var item_pool = loot_table.get(selected_rarity, [])
	if item_pool.is_empty():
		# Fall back to lower rarity if pool is empty
		for i in range(rarity_names.find(selected_rarity) - 1, -1, -1):
			item_pool = loot_table.get(rarity_names[i], [])
			if not item_pool.is_empty():
				selected_rarity = rarity_names[i]
				break
	
	if item_pool.is_empty():
		return {}
	
	var item_id = item_pool[randi() % item_pool.size()]
	var rarity_index = rarity_names.find(selected_rarity)
	
	return {
		"item_id": item_id,
		"rarity": rarity_index,
		"quantity": _get_item_quantity(item_id, rarity_index)
	}

func _get_item_quantity(item_id: String, rarity: int) -> int:
	# Ammo and consumables can stack
	var stackable_items = [
		"pistol_ammo", "rifle_ammo", "shotgun_ammo", "smg_ammo", "heavy_ammo",
		"special_ammo", "explosive_ammo", "rocket_ammo", "grenade_launcher_ammo",
		"bandage", "medkit_small", "medkit_large", "scrap_metal", "cloth",
		"gunpowder", "fuse", "chemical_compound"
	]
	
	if item_id in stackable_items:
		var base_quantity = 1
		match item_id:
			"pistol_ammo":
				base_quantity = randi_range(8, 15)
			"rifle_ammo":
				base_quantity = randi_range(10, 20)
			"shotgun_ammo":
				base_quantity = randi_range(4, 8)
			"smg_ammo":
				base_quantity = randi_range(15, 30)
			"heavy_ammo":
				base_quantity = randi_range(20, 40)
			"bandage":
				base_quantity = randi_range(1, 3)
			"scrap_metal", "cloth":
				base_quantity = randi_range(2, 5)
			_:
				base_quantity = randi_range(1, 3)
		
		# Higher rarity = more quantity
		return base_quantity + (rarity * randi_range(1, 3))
	
	return 1

# ============================================
# NETWORK SYNC (for dedicated server)
# ============================================

func serialize_wave_state() -> Dictionary:
	return {
		"current_wave": current_wave,
		"is_nightmare": is_nightmare_mode,
		"zombies_remaining": current_wave_zombies_remaining,
		"total_killed": total_zombies_killed
	}

func deserialize_wave_state(data: Dictionary):
	current_wave = data.get("current_wave", 0)
	is_nightmare_mode = data.get("is_nightmare", false)
	current_wave_zombies_remaining = data.get("zombies_remaining", 0)
	total_zombies_killed = data.get("total_killed", 0)

@rpc("authority", "call_remote", "reliable")
func sync_wave_state(data: Dictionary):
	deserialize_wave_state(data)

@rpc("authority", "call_remote", "reliable")
func sync_loot_drop(position: Vector3, items: Array):
	loot_dropped.emit(position, items)

# ============================================
# UTILITY
# ============================================

func get_wave_info_text(wave: int) -> String:
	var difficulty = get_wave_difficulty(wave)
	var text = "Wave %d\n" % wave
	text += "Zombies: %d\n" % difficulty.zombie_count
	text += "Health: x%.2f\n" % difficulty.health_multiplier
	text += "Damage: x%.2f\n" % difficulty.damage_multiplier
	
	if difficulty.is_boss_wave:
		text += "BOSS WAVE: %s\n" % _get_boss_name(difficulty.boss_type)
	
	if wave > NIGHTMARE_MODE_WAVE:
		text += "NIGHTMARE MODE ACTIVE\n"
	
	return text

func is_wave_complete() -> bool:
	return current_wave_zombies_remaining <= 0
