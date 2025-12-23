extends Node
class_name PointsSystem

# Worth/Points system like JetBoom's Zombie Survival

signal points_changed(new_points: int)
signal points_earned(amount: int, reason: String)
signal points_spent(amount: int, item_name: String)

@export var starting_points: int = 500
@export var wave_completion_bonus: int = 250

var current_points: int = 500
var total_points_earned: int = 0
var total_points_spent: int = 0

# Point rewards
const SHAMBLER_KILL: int = 100
const RUNNER_KILL: int = 120
const TANK_KILL: int = 200
const POISON_KILL: int = 150
const EXPLODER_KILL: int = 180
const BOSS_KILL: int = 1000

# Point bonuses
const HEADSHOT_BONUS: int = 25
const MELEE_BONUS: int = 50
const ASSIST_BONUS: int = 20

# Costs
const BARRICADE_COST: int = 50
const BARRICADE_REPAIR_COST: int = 25
const AMMO_COST: int = 100
const HEALTH_PACK_COST: int = 150

func _ready():
	current_points = starting_points
	points_changed.emit(current_points)

func add_points(amount: int, reason: String = ""):
	current_points += amount
	total_points_earned += amount
	points_changed.emit(current_points)
	points_earned.emit(amount, reason)

func spend_points(amount: int, item_name: String = "") -> bool:
	if current_points < amount:
		return false

	current_points -= amount
	total_points_spent += amount
	points_changed.emit(current_points)
	points_spent.emit(amount, item_name)

	return true

func can_afford(amount: int) -> bool:
	return current_points >= amount

# Zombie kill rewards
func reward_zombie_kill(zombie_class: String, was_headshot: bool = false, was_assist: bool = false) -> int:
	var points = 0

	match zombie_class:
		"Shambler": points = SHAMBLER_KILL
		"Runner": points = RUNNER_KILL
		"Tank": points = TANK_KILL
		"Poison": points = POISON_KILL
		"Exploder": points = EXPLODER_KILL
		_: points = SHAMBLER_KILL

	if was_headshot:
		points += HEADSHOT_BONUS

	if was_assist:
		points = int(points * 0.5)  # Half points for assists

	add_points(points, "Killed " + zombie_class)

	return points

func reward_boss_kill(boss_name: String) -> int:
	var points = BOSS_KILL
	add_points(points, "Killed Boss: " + boss_name)
	return points

func reward_wave_completion(wave_number: int) -> int:
	var points = wave_completion_bonus + (wave_number * 50)
	add_points(points, "Completed Wave " + str(wave_number))
	return points

func reward_barricade_repair() -> int:
	var points = 10
	add_points(points, "Repaired Barricade")
	return points

# Purchases
func buy_barricade() -> bool:
	return spend_points(BARRICADE_COST, "Barricade")

func buy_barricade_repair() -> bool:
	return spend_points(BARRICADE_REPAIR_COST, "Barricade Repair")

func buy_ammo() -> bool:
	return spend_points(AMMO_COST, "Ammo")

func buy_health_pack() -> bool:
	return spend_points(HEALTH_PACK_COST, "Health Pack")

func buy_weapon(weapon_name: String, cost: int) -> bool:
	return spend_points(cost, weapon_name)

# Stats
func get_points() -> int:
	return current_points

func get_total_earned() -> int:
	return total_points_earned

func get_total_spent() -> int:
	return total_points_spent

func get_net_points() -> int:
	return total_points_earned - total_points_spent

# Save/Load
func save_points_data() -> Dictionary:
	return {
		"current": current_points,
		"earned": total_points_earned,
		"spent": total_points_spent
	}

func load_points_data(data: Dictionary):
	current_points = data.get("current", starting_points)
	total_points_earned = data.get("earned", 0)
	total_points_spent = data.get("spent", 0)
	points_changed.emit(current_points)

func reset_points():
	current_points = starting_points
	total_points_earned = 0
	total_points_spent = 0
	points_changed.emit(current_points)
