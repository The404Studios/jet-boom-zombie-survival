extends Node
# Note: Do not use class_name here - this script is an autoload singleton

# Central event coordination hub
# Connects all game systems and broadcasts events between them
# Autoload singleton: GameEvents

# ============================================
# PLAYER EVENTS
# ============================================
signal player_spawned(peer_id: int, player: Node)
signal player_died(peer_id: int, killer_id: int, weapon: String, is_headshot: bool)
signal player_respawned(peer_id: int)
signal player_damaged(peer_id: int, damage: float, attacker_id: int, damage_type: String)
signal player_healed(peer_id: int, amount: float, source: String)
signal player_connected(peer_id: int, player_name: String)
signal player_disconnected(peer_id: int, player_name: String)

# ============================================
# ZOMBIE EVENTS
# ============================================
signal zombie_spawned(zombie: Node, zombie_type: String)
signal zombie_killed(zombie: Node, killer_id: int, weapon: String, is_headshot: bool)
signal zombie_damaged(zombie: Node, damage: float, attacker_id: int, damage_type: String)
signal boss_spawned(boss: Node, boss_name: String)
signal boss_killed(boss: Node, killer_id: int)

# ============================================
# ROUND/WAVE EVENTS
# ============================================
signal round_starting(round_number: int)
signal round_started(round_number: int)
signal round_ended(round_number: int, victory: bool)
signal wave_spawning(wave_number: int, zombie_count: int)
signal wave_cleared(wave_number: int)
signal intermission_started(duration: float)
signal intermission_ended
signal game_started
signal game_over(victory: bool)

# ============================================
# COMBAT EVENTS
# ============================================
signal damage_dealt(attacker_id: int, target: Node, damage: float, position: Vector3, is_crit: bool)
signal kill_confirmed(killer_id: int, victim_name: String, weapon: String, is_headshot: bool)
signal combo_achieved(player_id: int, combo_count: int)
signal headshot_landed(attacker_id: int, target: Node)

# ============================================
# ITEM/PICKUP EVENTS
# ============================================
signal item_picked_up(peer_id: int, item_name: String, amount: int)
signal weapon_picked_up(peer_id: int, weapon_name: String)
signal ammo_picked_up(peer_id: int, ammo_type: String, amount: int)
signal health_picked_up(peer_id: int, amount: float)
signal armor_picked_up(peer_id: int, amount: float)
signal powerup_activated(peer_id: int, powerup_type: String, duration: float)
signal powerup_expired(peer_id: int, powerup_type: String)

# ============================================
# CRAFTING/BUILDING EVENTS
# ============================================
signal prop_nailed(prop: Node, nailer_id: int, nail_count: int)
signal prop_destroyed(prop: Node)
signal barricade_built(position: Vector3, builder_id: int)
signal barricade_destroyed(position: Vector3)
signal item_crafted(peer_id: int, item_name: String)

# ============================================
# ACHIEVEMENT/PROGRESSION EVENTS
# ============================================
signal achievement_unlocked(peer_id: int, achievement_id: String)
signal xp_gained(peer_id: int, amount: int, source: String)
signal level_up(peer_id: int, new_level: int)
signal points_earned(peer_id: int, amount: int, source: String)

# ============================================
# UI EVENTS
# ============================================
signal show_notification(text: String, type: int)
signal show_announcement(title: String, subtitle: String)
signal update_objective(text: String)
signal show_damage_indicator(direction: Vector3, damage: float)

# ============================================
# SYSTEM REFERENCES
# ============================================
var player_manager: Node = null
var round_manager: Node = null
var wave_manager: Node = null
var spawn_manager: Node = null
var notification_manager: Node = null
var damage_numbers_manager: Node = null
var kill_feed: Node = null
var scoreboard: Node = null

# Local player reference
var local_player: Node = null
var local_peer_id: int = 1

# Stats tracking
var session_stats: Dictionary = {
	"kills": 0,
	"deaths": 0,
	"damage_dealt": 0,
	"damage_taken": 0,
	"headshots": 0,
	"zombies_killed": 0,
	"rounds_survived": 0,
	"items_picked_up": 0
}

func _ready():
	# Get local peer ID
	if multiplayer.has_multiplayer_peer():
		local_peer_id = multiplayer.get_unique_id()

	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Defer system binding to allow other autoloads to initialize
	call_deferred("_bind_systems")

func _bind_systems():
	# Find and bind all game systems
	player_manager = get_node_or_null("/root/PlayerManager")
	round_manager = get_node_or_null("/root/RoundManager")
	wave_manager = get_node_or_null("/root/WaveManager")
	spawn_manager = get_node_or_null("/root/SpawnManager")
	notification_manager = get_node_or_null("/root/NotificationManager")
	damage_numbers_manager = get_node_or_null("/root/DamageNumbers")

	# Connect player manager signals
	if player_manager:
		if player_manager.has_signal("player_spawned"):
			player_manager.player_spawned.connect(_on_player_manager_spawned)
		if player_manager.has_signal("player_died"):
			player_manager.player_died.connect(_on_player_manager_died)
		if player_manager.has_signal("player_respawned"):
			player_manager.player_respawned.connect(_on_player_manager_respawned)

	# Connect round manager signals
	if round_manager:
		if round_manager.has_signal("round_started"):
			round_manager.round_started.connect(_on_round_started)
		if round_manager.has_signal("round_ended"):
			round_manager.round_ended.connect(_on_round_ended)
		if round_manager.has_signal("game_over"):
			round_manager.game_over.connect(_on_game_over)
		if round_manager.has_signal("intermission_started"):
			round_manager.intermission_started.connect(_on_intermission_started)

	# Connect wave manager signals
	if wave_manager:
		if wave_manager.has_signal("wave_started"):
			wave_manager.wave_started.connect(_on_wave_started)
		if wave_manager.has_signal("wave_completed"):
			wave_manager.wave_completed.connect(_on_wave_completed)
		if wave_manager.has_signal("zombie_spawned"):
			wave_manager.zombie_spawned.connect(_on_zombie_spawned)
		if wave_manager.has_signal("boss_spawned"):
			wave_manager.boss_spawned.connect

# ============================================
# PLAYER EVENT HANDLERS
# ============================================

func _on_player_manager_spawned(peer_id: int, player: Node):
	player_spawned.emit(peer_id, player)

	if peer_id == local_peer_id:
		local_player = player

func _on_player_manager_died(peer_id: int, killer_id: int):
	# Emit with default values - actual weapon/headshot tracked elsewhere
	player_died.emit(peer_id, killer_id, "unknown", false)

	if peer_id == local_peer_id:
		session_stats.deaths += 1

func _on_player_manager_respawned(peer_id: int):
	player_respawned.emit(peer_id)

func _on_peer_connected(peer_id: int):
	var player_name = "Player %d" % peer_id
	if player_manager and player_manager.has_method("get_player_data"):
		var data = player_manager.get_player_data(peer_id)
		if data:
			player_name = data.player_name

	player_connected.emit(peer_id, player_name)

	# Show notification
	if notification_manager:
		notification_manager.notify_player_joined(player_name)

func _on_peer_disconnected(peer_id: int):
	var player_name = "Player %d" % peer_id
	if player_manager and player_manager.has_method("get_player_data"):
		var data = player_manager.get_player_data(peer_id)
		if data:
			player_name = data.player_name

	player_disconnected.emit(peer_id, player_name)

	if notification_manager:
		notification_manager.notify_player_left(player_name)

# ============================================
# ROUND/WAVE EVENT HANDLERS
# ============================================

func _on_round_started(round_num: int):
	round_started.emit(round_num)

	if notification_manager:
		notification_manager.notify_wave_start(round_num)

func _on_round_ended(round_num: int, victory: bool):
	round_ended.emit(round_num, victory)
	session_stats.rounds_survived += 1

	if notification_manager:
		notification_manager.notify_wave_complete(round_num)

func _on_game_over(victory: bool):
	game_over.emit(victory)

	if notification_manager:
		notification_manager.notify_game_over(victory)

func _on_intermission_started(duration: float):
	intermission_started.emit(duration)

	if notification_manager:
		notification_manager.notify_intermission(int(duration))

func _on_wave_started(wave_num: int):
	wave_spawning.emit(wave_num, 0)

func _on_wave_completed(wave_num: int):
	wave_cleared.emit(wave_num)

func _on_zombie_spawned(zombie: Node):
	var zombie_type = "Zombie"
	if zombie.has_method("get_zombie_type"):
		zombie_type = zombie.get_zombie_type()

	zombie_spawned.emit(zombie, zombie_type)

# ============================================
# COMBAT EVENT BROADCASTING
# ============================================

func report_damage(attacker_id: int, target: Node, damage: float, position: Vector3,
				   is_crit: bool = false, damage_type: String = "normal"):
	"""Report damage dealt - call this from weapons/damage sources"""
	damage_dealt.emit(attacker_id, target, damage, position, is_crit)

	# Spawn damage number
	if damage_numbers_manager:
		if is_crit:
			damage_numbers_manager.spawn_damage(position, damage, true)
		else:
			damage_numbers_manager.spawn_damage(position, damage, false)

	# Track stats for local player
	if attacker_id == local_peer_id:
		session_stats.damage_dealt += damage

	# Check if target is zombie
	if target.is_in_group("zombies"):
		zombie_damaged.emit(target, damage, attacker_id, damage_type)
	elif target.is_in_group("players"):
		# Get target peer_id
		var target_peer_id = target.get("peer_id")
		if target_peer_id:
			player_damaged.emit(target_peer_id, damage, attacker_id, damage_type)
			if target_peer_id == local_peer_id:
				session_stats.damage_taken += damage

func report_kill(killer_id: int, victim: Node, weapon: String = "unknown",
				 is_headshot: bool = false):
	"""Report a kill - call this when an entity dies"""
	var victim_name = "Unknown"

	if victim.is_in_group("zombies"):
		# Zombie kill
		var zombie_type = "Zombie"
		if victim.has_method("get_zombie_type"):
			zombie_type = victim.get_zombie_type()

		victim_name = zombie_type
		zombie_killed.emit(victim, killer_id, weapon, is_headshot)

		# Update kill feed
		if kill_feed and killer_id > 0:
			var killer_name = _get_player_name(killer_id)
			kill_feed.add_zombie_kill(killer_name, zombie_type, weapon, is_headshot,
									  killer_id == local_peer_id)

		# Track stats
		if killer_id == local_peer_id:
			session_stats.zombies_killed += 1
			session_stats.kills += 1
			if is_headshot:
				session_stats.headshots += 1

	elif victim.is_in_group("players"):
		# Player kill
		var victim_peer_id = victim.get("peer_id")
		if victim_peer_id:
			victim_name = _get_player_name(victim_peer_id)
			player_died.emit(victim_peer_id, killer_id, weapon, is_headshot)

			# Update kill feed
			if kill_feed:
				var killer_name = _get_player_name(killer_id) if killer_id > 0 else "Zombie"
				kill_feed.add_kill(killer_name, victim_name, weapon, is_headshot,
								   killer_id == local_peer_id, victim_peer_id == local_peer_id)

			if killer_id == local_peer_id:
				session_stats.kills += 1
				if is_headshot:
					session_stats.headshots += 1

	elif victim.is_in_group("bosses"):
		# Boss kill
		var boss_name = victim.get("boss_name") if victim.has("boss_name") else "Boss"
		boss_killed.emit(victim, killer_id)

		if notification_manager:
			notification_manager.announce("BOSS DEFEATED", boss_name)

	# Emit generic kill confirmed
	kill_confirmed.emit(killer_id, victim_name, weapon, is_headshot)

	# Headshot event
	if is_headshot:
		headshot_landed.emit(killer_id, victim)

func report_heal(peer_id: int, amount: float, position: Vector3, source: String = ""):
	"""Report healing"""
	player_healed.emit(peer_id, amount, source)

	if damage_numbers_manager:
		damage_numbers_manager.spawn_heal(position, amount)

func report_headshot(attacker_id: int, target: Node, position: Vector3):
	"""Report a headshot hit"""
	headshot_landed.emit(attacker_id, target)

	# Visual feedback
	if damage_numbers_manager:
		damage_numbers_manager.spawn_text(position + Vector3.UP * 0.3, "HEADSHOT!", Color(1, 0.8, 0))

# ============================================
# ITEM/PICKUP EVENT BROADCASTING
# ============================================

func report_item_pickup(peer_id: int, item_name: String, amount: int = 1):
	"""Report item pickup"""
	item_picked_up.emit(peer_id, item_name, amount)

	if peer_id == local_peer_id:
		session_stats.items_picked_up += 1
		if notification_manager:
			notification_manager.notify_pickup(item_name, amount)

func report_weapon_pickup(peer_id: int, weapon_name: String):
	"""Report weapon pickup"""
	weapon_picked_up.emit(peer_id, weapon_name)

	if peer_id == local_peer_id and notification_manager:
		notification_manager.notify_pickup(weapon_name)

func report_ammo_pickup(peer_id: int, ammo_type: String, amount: int):
	"""Report ammo pickup"""
	ammo_picked_up.emit(peer_id, ammo_type, amount)

	if peer_id == local_peer_id and notification_manager:
		notification_manager.notify_pickup("%s Ammo" % ammo_type.capitalize(), amount)

func report_health_pickup(peer_id: int, amount: float, position: Vector3):
	"""Report health pickup"""
	health_picked_up.emit(peer_id, amount)
	report_heal(peer_id, amount, position, "pickup")

func report_powerup(peer_id: int, powerup_type: String, duration: float):
	"""Report powerup activation"""
	powerup_activated.emit(peer_id, powerup_type, duration)

	if peer_id == local_peer_id and notification_manager:
		notification_manager.notify("%s activated!" % powerup_type.capitalize(),
									notification_manager.NotificationType.SUCCESS)

# ============================================
# BUILDING/CRAFTING EVENTS
# ============================================

func report_prop_nailed(prop: Node, nailer_id: int, nail_count: int):
	"""Report prop being nailed"""
	prop_nailed.emit(prop, nailer_id, nail_count)

func report_prop_destroyed(prop: Node):
	"""Report prop destroyed"""
	prop_destroyed.emit(prop)

func report_item_crafted(peer_id: int, item_name: String):
	"""Report item crafted"""
	item_crafted.emit(peer_id, item_name)

	if peer_id == local_peer_id and notification_manager:
		notification_manager.notify("Crafted: " + item_name,
									notification_manager.NotificationType.SUCCESS)

# ============================================
# ACHIEVEMENT/PROGRESSION EVENTS
# ============================================

func report_achievement(peer_id: int, achievement_id: String, achievement_name: String):
	"""Report achievement unlocked"""
	achievement_unlocked.emit(peer_id, achievement_id)

	if peer_id == local_peer_id and notification_manager:
		notification_manager.notify_achievement(achievement_name)

func report_xp_gain(peer_id: int, amount: int, position: Vector3, source: String = ""):
	"""Report XP gained"""
	xp_gained.emit(peer_id, amount, source)

	if damage_numbers_manager:
		damage_numbers_manager.spawn_xp(position, amount)

func report_points(peer_id: int, amount: int, position: Vector3, source: String = ""):
	"""Report points earned"""
	points_earned.emit(peer_id, amount, source)

	if damage_numbers_manager:
		damage_numbers_manager.spawn_points(position, amount)

func report_level_up(peer_id: int, new_level: int):
	"""Report level up"""
	level_up.emit(peer_id, new_level)

	if peer_id == local_peer_id and notification_manager:
		notification_manager.announce("LEVEL UP!", "You are now level %d" % new_level)

# ============================================
# COMBO SYSTEM
# ============================================

var combo_counts: Dictionary = {}  # peer_id -> combo count
var combo_timers: Dictionary = {}  # peer_id -> timer
const COMBO_TIMEOUT: float = 2.0

func add_combo_kill(peer_id: int, position: Vector3):
	"""Add a kill to player's combo"""
	if not combo_counts.has(peer_id):
		combo_counts[peer_id] = 0

	combo_counts[peer_id] += 1
	combo_timers[peer_id] = COMBO_TIMEOUT

	var count = combo_counts[peer_id]
	if count >= 3:
		combo_achieved.emit(peer_id, count)

		if damage_numbers_manager:
			damage_numbers_manager.combo_count = count
			damage_numbers_manager.spawn_combo(position)

func _process(delta):
	# Update combo timers
	for peer_id in combo_timers.keys():
		combo_timers[peer_id] -= delta
		if combo_timers[peer_id] <= 0:
			combo_counts.erase(peer_id)
			combo_timers.erase(peer_id)

# ============================================
# UTILITY
# ============================================

func _get_player_name(peer_id: int) -> String:
	if player_manager and player_manager.has_method("get_player_data"):
		var data = player_manager.get_player_data(peer_id)
		if data:
			return data.player_name

	if peer_id == local_peer_id:
		return "You"

	return "Player %d" % peer_id

func get_session_stats() -> Dictionary:
	return session_stats.duplicate()

func reset_session_stats():
	session_stats = {
		"kills": 0,
		"deaths": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"headshots": 0,
		"zombies_killed": 0,
		"rounds_survived": 0,
		"items_picked_up": 0
	}

func set_local_player(player: Node):
	local_player = player

func get_local_player() -> Node:
	return local_player

# ============================================
# UI BINDING (call from UI scripts)
# ============================================

func bind_kill_feed(feed: Node):
	kill_feed = feed

func bind_scoreboard(board: Node):
	scoreboard = board

func bind_notification_manager(manager: Node):
	notification_manager = manager

func bind_damage_numbers(manager: Node):
	damage_numbers_manager = manager
