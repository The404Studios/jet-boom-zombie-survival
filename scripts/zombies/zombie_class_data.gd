extends Resource
class_name ZombieClassData

enum ZombieClass {
	SHAMBLER,      # Basic slow zombie
	RUNNER,        # Fast zombie
	TANK,          # High HP, slow
	POISON,        # Poison on hit
	EXPLODER,      # Explodes on death
	SPITTER,       # Ranged acid attack
	SCREAMER,      # Buffs nearby zombies
	BERSERKER,     # High damage, medium speed
	BOOMER,        # Explodes bile on death
	BOSS_BEHEMOTH, # Tank boss
	BOSS_NIGHTMARE,# Fast boss
	BOSS_ABOMINATION # Special boss
}

@export var class_name: String = "Shambler"
@export var zombie_class: ZombieClass = ZombieClass.SHAMBLER
@export var description: String = ""

# Base Stats
@export var base_health: float = 100.0
@export var base_move_speed: float = 3.0
@export var base_damage: float = 10.0
@export var base_armor: float = 0.0
@export var attack_range: float = 2.0
@export var attack_speed: float = 1.5

# Scaling per Wave
@export var health_per_wave: float = 20.0
@export var damage_per_wave: float = 2.0
@export var armor_per_wave: float = 1.0

# Rewards
@export var points_reward: int = 100
@export var experience_reward: int = 50

# Special Properties
@export var can_break_barricades: bool = true
@export var barricade_damage: float = 5.0
@export var is_boss: bool = false
@export var boss_music: AudioStream = null
@export var spawn_cost: int = 1  # How many spawn points this zombie costs

# Abilities
@export var has_poison: bool = false
@export var poison_damage_per_second: float = 5.0
@export var has_explosion: bool = false
@export var explosion_damage: float = 50.0
@export var explosion_radius: float = 5.0
@export var has_ranged_attack: bool = false
@export var ranged_attack_cooldown: float = 3.0
@export var ranged_damage: float = 15.0
@export var ranged_range: float = 15.0
@export var buff_nearby_zombies: bool = false
@export var buff_radius: float = 10.0
@export var buff_amount: float = 0.2

# Additional Abilities
@export var has_buff_aura: bool = false
@export var buff_speed_multiplier: float = 1.0
@export var buff_damage_multiplier: float = 1.0
@export var scream_cooldown: float = 10.0

@export var has_rage_mode: bool = false
@export var rage_threshold: float = 0.5  # Activate when health below this %
@export var rage_speed_bonus: float = 1.5
@export var rage_damage_bonus: float = 1.3

@export var has_gas_cloud: bool = false
@export var gas_damage_per_second: float = 5.0
@export var gas_radius: float = 5.0
@export var gas_duration: float = 3.0
@export var gas_slow_amount: float = 0.5

@export var has_teleport: bool = false
@export var teleport_cooldown: float = 10.0
@export var teleport_range: float = 15.0

@export var can_summon_zombies: bool = false
@export var summon_cooldown: float = 20.0
@export var summon_count: int = 2

@export var has_regeneration: bool = false
@export var regeneration_per_second: float = 5.0

@export var has_aoe_attack: bool = false
@export var aoe_damage: float = 30.0
@export var aoe_radius: float = 5.0
@export var aoe_cooldown: float = 10.0

# Visual
@export var model_scale: float = 1.0
@export var tint_color: Color = Color.WHITE
@export var emission_color: Color = Color.BLACK
@export var emission_strength: float = 0.0

# Loot
@export var loot_multiplier: float = 1.0
@export var guaranteed_drop: bool = false

func get_scaled_health(wave: int) -> float:
	return base_health + (health_per_wave * (wave - 1))

func get_scaled_damage(wave: int) -> float:
	return base_damage + (damage_per_wave * (wave - 1))

func get_scaled_armor(wave: int) -> float:
	return base_armor + (armor_per_wave * (wave - 1))

func get_points_for_wave(wave: int) -> int:
	return int(points_reward * (1.0 + (wave * 0.1)))

func get_spawn_weight(wave: int) -> float:
	# Determine how likely this zombie is to spawn based on wave
	match zombie_class:
		ZombieClass.SHAMBLER:
			return max(1.0 - (wave * 0.05), 0.3)  # Less common in later waves
		ZombieClass.RUNNER:
			return 0.5 if wave >= 3 else 0.2
		ZombieClass.TANK:
			return 0.3 if wave >= 5 else 0.0
		ZombieClass.POISON:
			return 0.4 if wave >= 4 else 0.0
		ZombieClass.EXPLODER:
			return 0.3 if wave >= 6 else 0.0
		ZombieClass.SPITTER:
			return 0.2 if wave >= 7 else 0.0
		ZombieClass.SCREAMER:
			return 0.15 if wave >= 8 else 0.0
		ZombieClass.BERSERKER:
			return 0.4 if wave >= 5 else 0.0
		ZombieClass.BOOMER:
			return 0.25 if wave >= 6 else 0.0
	return 0.0
