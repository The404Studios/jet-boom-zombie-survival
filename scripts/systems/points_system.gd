extends Node
# Note: Do not use class_name here - this script is an autoload singleton
# Access via: PointsSystem (the autoload name)

# Worth/Points system like JetBoom's Zombie Survival
# Now also manages Sigils (shop currency)

signal points_changed(new_points: int)
signal points_earned(amount: int, reason: String)
signal points_spent(amount: int, item_name: String)
signal sigils_changed(new_sigils: int)
signal sigils_earned(amount: int, reason: String)

@export var starting_points: int = 500
@export var starting_sigils: int = 500
@export var wave_completion_bonus: int = 250

var current_points: int = 500
var total_points_earned: int = 0
var total_points_spent: int = 0

# Sigil system
var current_sigils: int = 500
var total_sigils_earned: int = 0
var total_sigils_spent: int = 0

# Backend integration
var backend: Node = null
var websocket_hub: Node = null
var _pending_backend_sync: bool = false

# Sigil conversion rate (points to sigils)
const SIGIL_CONVERSION_RATE: float = 0.1  # 10% of points earned as sigils

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
	current_sigils = starting_sigils
	points_changed.emit(current_points)
	sigils_changed.emit(current_sigils)

	# Initialize backend integration
	_init_backend()

	# Sync with persistence if available
	await get_tree().create_timer(0.2).timeout
	_sync_from_persistence()

func _init_backend():
	backend = get_node_or_null("/root/Backend")
	websocket_hub = get_node_or_null("/root/WebSocketHub")

	if backend:
		if backend.has_signal("logged_in"):
			backend.logged_in.connect(_on_backend_logged_in)
		if backend.has_signal("logged_out"):
			backend.logged_out.connect(_on_backend_logged_out)

func _on_backend_logged_in(player_data: Dictionary):
	"""Sync sigils from backend on login"""
	var backend_currency = player_data.get("currency", 0)
	if backend_currency > 0:
		current_sigils = backend_currency
		sigils_changed.emit(current_sigils)
		print("Sigils synced from backend: %d" % current_sigils)

func _on_backend_logged_out():
	"""Reset to local persistence on logout"""
	_sync_from_persistence()

func _sync_from_persistence():
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		var saved_sigils = persistence.get_currency("sigils")
		if saved_sigils > 0:
			current_sigils = saved_sigils
			sigils_changed.emit(current_sigils)

func add_points(amount: int, reason: String = ""):
	current_points += amount
	total_points_earned += amount
	points_changed.emit(current_points)
	points_earned.emit(amount, reason)

	# Also award sigils based on points earned
	var sigil_bonus = int(amount * SIGIL_CONVERSION_RATE)
	if sigil_bonus > 0:
		add_sigils(sigil_bonus, reason)

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

# ============================================
# SIGIL MANAGEMENT
# ============================================

func add_sigils(amount: int, reason: String = ""):
	current_sigils += amount
	total_sigils_earned += amount
	sigils_changed.emit(current_sigils)
	sigils_earned.emit(amount, reason)

	# Sync with persistence
	if has_node("/root/PlayerPersistence"):
		get_node("/root/PlayerPersistence").add_currency("sigils", amount)

	# Sync with backend
	_sync_sigils_to_backend()

func spend_sigils(amount: int) -> bool:
	if current_sigils < amount:
		return false

	current_sigils -= amount
	total_sigils_spent += amount
	sigils_changed.emit(current_sigils)

	# Sync with persistence
	if has_node("/root/PlayerPersistence"):
		get_node("/root/PlayerPersistence").spend_currency("sigils", amount)

	# Sync with backend
	_sync_sigils_to_backend()

	return true

func can_afford_sigils(amount: int) -> bool:
	return current_sigils >= amount

func get_sigils() -> int:
	return current_sigils

func get_total_sigils_earned() -> int:
	return total_sigils_earned

func get_total_sigils_spent() -> int:
	return total_sigils_spent

# ============================================
# SPECIAL SIGIL REWARDS
# ============================================

func reward_wave_sigils(wave_number: int):
	"""Award bonus sigils for completing a wave"""
	var sigils = 50 + (wave_number * 25)  # 75, 100, 125, etc.
	add_sigils(sigils, "Wave %d Complete" % wave_number)

func reward_boss_sigils(boss_name: String):
	"""Award sigils for killing a boss"""
	add_sigils(200, "Killed " + boss_name)

func reward_extraction_sigils():
	"""Award sigils for successful extraction"""
	add_sigils(100, "Extraction Bonus")

func reward_headshot_sigils():
	"""Small sigil bonus for headshots"""
	add_sigils(5, "Headshot")

# ============================================
# SAVE/LOAD
# ============================================

func save_points_data() -> Dictionary:
	return {
		"current": current_points,
		"earned": total_points_earned,
		"spent": total_points_spent,
		"sigils_current": current_sigils,
		"sigils_earned": total_sigils_earned,
		"sigils_spent": total_sigils_spent
	}

func load_points_data(data: Dictionary):
	current_points = data.get("current", starting_points)
	total_points_earned = data.get("earned", 0)
	total_points_spent = data.get("spent", 0)
	current_sigils = data.get("sigils_current", starting_sigils)
	total_sigils_earned = data.get("sigils_earned", 0)
	total_sigils_spent = data.get("sigils_spent", 0)
	points_changed.emit(current_points)
	sigils_changed.emit(current_sigils)

func reset_points():
	current_points = starting_points
	total_points_earned = 0
	total_points_spent = 0
	current_sigils = starting_sigils
	total_sigils_earned = 0
	total_sigils_spent = 0
	points_changed.emit(current_points)
	sigils_changed.emit(current_sigils)

# ============================================
# BACKEND SYNC
# ============================================

func _sync_sigils_to_backend():
	"""Sync current sigil balance to backend"""
	if not backend or not backend.is_authenticated:
		return

	# Debounce sync calls
	if _pending_backend_sync:
		return
	_pending_backend_sync = true

	# Wait a moment to batch updates
	await get_tree().create_timer(0.5).timeout
	_pending_backend_sync = false

	if not backend or not backend.is_authenticated:
		return

	# Update backend with current sigil balance
	var update_data = {
		"currency": current_sigils
	}

	backend.update_profile(update_data, func(response):
		if response.success:
			print("Sigils synced to backend: %d" % current_sigils)
	)

func sync_stats_to_backend():
	"""Sync point stats at end of match"""
	if not backend or not backend.is_authenticated:
		return

	var stat_update = {
		"pointsEarned": total_points_earned,
		"pointsSpent": total_points_spent,
		"sigilsEarned": total_sigils_earned,
		"sigilsSpent": total_sigils_spent
	}

	backend.update_stats(stat_update, func(response):
		if response.success:
			print("Point stats synced to backend")
	)

func fetch_sigils_from_backend():
	"""Fetch current sigil balance from backend"""
	if not backend or not backend.is_authenticated:
		return

	if backend.current_player:
		var backend_sigils = backend.current_player.get("currency", 0)
		if backend_sigils > 0:
			current_sigils = backend_sigils
			sigils_changed.emit(current_sigils)
