extends Node
class_name WaveManager

signal wave_started(wave_number: int, zombie_count: int)
signal wave_completed(wave_number: int)
signal intermission_started(duration: float)
signal intermission_ended
signal boss_wave(wave_number: int)
signal all_zombies_dead
signal zombie_spawned(zombie: Node3D, zombie_class: ZombieClassData)

@export var zombie_scene: PackedScene
@export var spawn_points: Array[Node3D] = []
@export var zombie_classes: Array[ZombieClassData] = []

# Wave Configuration
@export var starting_zombie_count: int = 10
@export var zombies_per_wave_increase: int = 5
@export var max_zombies_alive: int = 30
@export var intermission_duration: float = 30.0
@export var boss_wave_interval: int = 5  # Boss every 5 waves
@export var spawn_delay: float = 2.0

# Current State
var current_wave: int = 0
var zombies_to_spawn: int = 0
var zombies_spawned_this_wave: int = 0
var zombies_alive: int = 0
var zombies_killed_this_wave: int = 0
var total_zombies_killed: int = 0

var is_wave_active: bool = false
var is_intermission: bool = false
var intermission_timer: float = 0.0
var spawn_timer: float = 0.0

var zombie_spawn_queue: Array[ZombieClassData] = []
var active_zombies: Array[Node3D] = []

# Network replication
var is_network_authority: bool = true

# Backend integration
var backend: Node = null
var websocket_hub: Node = null

func _ready():
	# Check if we're the network authority
	is_network_authority = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

	# Initialize backend
	_init_backend()

	# Load zombie classes if not set
	if zombie_classes.is_empty():
		load_default_zombie_classes()

	# Only server starts waves
	if is_network_authority:
		# Start first wave after delay
		await get_tree().create_timer(5.0).timeout
		if not is_instance_valid(self) or not is_inside_tree():
			return
		start_next_wave()
	else:
		# Clients request initial state
		_request_wave_state.rpc_id(1)

func _init_backend():
	backend = get_node_or_null("/root/Backend")
	websocket_hub = get_node_or_null("/root/WebSocketHub")

	if websocket_hub:
		if websocket_hub.has_signal("wave_state_update"):
			websocket_hub.wave_state_update.connect(_on_backend_wave_update)

func _process(delta):
	if is_intermission:
		intermission_timer -= delta
		if intermission_timer <= 0:
			end_intermission()
		return

	if is_wave_active:
		# Spawn zombies from queue
		if zombie_spawn_queue.size() > 0 and zombies_alive < max_zombies_alive:
			spawn_timer -= delta
			if spawn_timer <= 0:
				spawn_next_zombie()
				spawn_timer = spawn_delay

		# Check if wave is complete
		if zombies_spawned_this_wave >= zombies_to_spawn and zombies_alive <= 0:
			complete_wave()

func start_next_wave():
	# Only server can start waves
	if not is_network_authority:
		return

	current_wave += 1
	is_wave_active = true
	is_intermission = false

	# Calculate zombies for this wave
	zombies_to_spawn = starting_zombie_count + ((current_wave - 1) * zombies_per_wave_increase)
	zombies_spawned_this_wave = 0
	zombies_killed_this_wave = 0

	# Check if boss wave
	var is_boss_wave = (current_wave % boss_wave_interval) == 0

	# Generate spawn queue
	generate_spawn_queue(is_boss_wave)

	wave_started.emit(current_wave, zombies_to_spawn)

	if is_boss_wave:
		boss_wave.emit(current_wave)

	print("Wave %d started! %d zombies incoming!" % [current_wave, zombies_to_spawn])

	# Network replicate wave start
	if multiplayer.has_multiplayer_peer():
		_sync_wave_start.rpc(current_wave, zombies_to_spawn, is_boss_wave)

	# Sync to backend
	_sync_wave_to_backend()

func generate_spawn_queue(include_boss: bool):
	zombie_spawn_queue.clear()

	var spawn_budget = zombies_to_spawn
	var spawned_count = 0

	# Boss first if boss wave
	if include_boss:
		var boss_class = get_boss_for_wave(current_wave)
		if boss_class:
			zombie_spawn_queue.append(boss_class)
			spawn_budget -= boss_class.spawn_cost
			spawned_count += boss_class.spawn_cost

	# Fill rest with regular zombies
	while spawned_count < zombies_to_spawn:
		var zombie_class = select_random_zombie_class()
		if zombie_class and spawned_count + zombie_class.spawn_cost <= zombies_to_spawn:
			zombie_spawn_queue.append(zombie_class)
			spawned_count += zombie_class.spawn_cost
		else:
			# If can't fit, use basic shambler
			var shambler = get_zombie_class(ZombieClassData.ZombieClass.SHAMBLER)
			if shambler:
				zombie_spawn_queue.append(shambler)
				spawned_count += 1

	# Shuffle for variety
	zombie_spawn_queue.shuffle()

func select_random_zombie_class() -> ZombieClassData:
	if zombie_classes.is_empty():
		return null

	# Build weighted list
	var weights: Array[float] = []
	var total_weight = 0.0

	for zombie_class in zombie_classes:
		if zombie_class.is_boss:
			continue
		var weight = zombie_class.get_spawn_weight(current_wave)
		weights.append(weight)
		total_weight += weight

	if total_weight <= 0:
		return zombie_classes[0] if not zombie_classes.is_empty() else null

	# Random selection based on weight
	var random = randf() * total_weight
	var cumulative = 0.0

	for i in range(zombie_classes.size()):
		if zombie_classes[i].is_boss:
			continue
		cumulative += weights[i]
		if random <= cumulative:
			return zombie_classes[i]

	return zombie_classes[0] if not zombie_classes.is_empty() else null

func get_zombie_class(type: ZombieClassData.ZombieClass) -> ZombieClassData:
	for zombie_class in zombie_classes:
		if zombie_class.zombie_class == type:
			return zombie_class
	return null

func get_boss_for_wave(wave: int) -> ZombieClassData:
	# Cycle through boss types
	var boss_types = [
		ZombieClassData.ZombieClass.BOSS_BEHEMOTH,
		ZombieClassData.ZombieClass.BOSS_NIGHTMARE,
		ZombieClassData.ZombieClass.BOSS_ABOMINATION
	]

	var boss_index = int(wave / boss_wave_interval - 1) % boss_types.size()
	return get_zombie_class(boss_types[boss_index])

func spawn_next_zombie():
	if zombie_spawn_queue.is_empty() or spawn_points.is_empty():
		return

	var zombie_class = zombie_spawn_queue.pop_front()
	var spawn_point = spawn_points[randi() % spawn_points.size()]

	var zombie: Node = null

	# Try to use object pool first
	var pool_manager = get_node_or_null("/root/ObjectPoolManager")
	if pool_manager and pool_manager.has_method("acquire"):
		zombie = pool_manager.acquire("zombie")

	# Fallback to instantiation
	if not zombie and zombie_scene:
		zombie = zombie_scene.instantiate()

	if not zombie:
		return

	var scene = get_tree().current_scene
	if not scene:
		if pool_manager:
			pool_manager.release("zombie", zombie)
		else:
			zombie.queue_free()
		return

	# Ensure zombie is in scene
	if zombie.get_parent() != scene:
		if zombie.get_parent():
			zombie.get_parent().remove_child(zombie)
		scene.add_child(zombie)

	zombie.global_position = spawn_point.global_position

	# Apply class data
	if zombie.has_method("setup_from_class"):
		zombie.setup_from_class(zombie_class, current_wave)

	# Connect signals (check if already connected)
	if zombie.has_signal("zombie_died"):
		if not zombie.zombie_died.is_connected(_on_zombie_died):
			zombie.zombie_died.connect(_on_zombie_died)

	# Register with performance optimizer
	var perf_opt = get_node_or_null("/root/PerformanceOptimizer")
	if perf_opt and perf_opt.has_method("register_node"):
		perf_opt.register_node(zombie, "normal")

	active_zombies.append(zombie)
	zombies_spawned_this_wave += 1
	zombies_alive += 1

	zombie_spawned.emit(zombie, zombie_class)

func _on_zombie_died(zombie: Node, _points: int = 0, _experience: int = 0):
	zombies_alive -= 1
	zombies_killed_this_wave += 1
	total_zombies_killed += 1

	if zombie in active_zombies:
		active_zombies.erase(zombie)

	if zombies_alive <= 0:
		all_zombies_dead.emit()

func complete_wave():
	# Only server completes waves
	if not is_network_authority:
		return

	is_wave_active = false
	wave_completed.emit(current_wave)

	print("Wave %d complete! %d zombies killed" % [current_wave, zombies_killed_this_wave])

	# Network replicate wave complete
	if multiplayer.has_multiplayer_peer():
		_sync_wave_complete.rpc(current_wave, zombies_killed_this_wave)

	# Sync to backend
	_sync_wave_to_backend()

	# Start intermission
	start_intermission()

func start_intermission():
	is_intermission = true
	intermission_timer = intermission_duration
	intermission_started.emit(intermission_duration)

	print("Intermission: %d seconds to prepare!" % int(intermission_duration))

	# Network replicate intermission
	if multiplayer.has_multiplayer_peer() and is_network_authority:
		_sync_intermission_start.rpc(intermission_duration)

func end_intermission():
	is_intermission = false
	intermission_ended.emit()

	# Network replicate intermission end
	if multiplayer.has_multiplayer_peer() and is_network_authority:
		_sync_intermission_end.rpc()

	start_next_wave()

func get_zombies_remaining() -> int:
	return zombie_spawn_queue.size() + zombies_alive

func get_wave_progress() -> float:
	if zombies_to_spawn <= 0:
		return 0.0
	return float(zombies_killed_this_wave) / float(zombies_to_spawn)

func force_next_wave():
	# Kill all zombies and skip to next wave
	for zombie in active_zombies:
		if is_instance_valid(zombie):
			zombie.queue_free()
	active_zombies.clear()
	zombies_alive = 0
	zombie_spawn_queue.clear()

	if is_intermission:
		end_intermission()
	else:
		complete_wave()

func load_default_zombie_classes():
	# Create default zombie classes
	zombie_classes.clear()

	# Shambler
	var shambler = ZombieClassData.new()
	shambler.display_name = "Shambler"
	shambler.zombie_class = ZombieClassData.ZombieClass.SHAMBLER
	shambler.base_health = 100.0
	shambler.base_move_speed = 2.5
	shambler.base_damage = 10.0
	shambler.points_reward = 100
	shambler.spawn_cost = 1
	zombie_classes.append(shambler)

	# Runner
	var runner = ZombieClassData.new()
	runner.display_name = "Runner"
	runner.zombie_class = ZombieClassData.ZombieClass.RUNNER
	runner.base_health = 60.0
	runner.base_move_speed = 6.0
	runner.base_damage = 8.0
	runner.points_reward = 120
	runner.spawn_cost = 1
	runner.tint_color = Color(1.0, 0.8, 0.8)
	zombie_classes.append(runner)

	# Tank
	var tank = ZombieClassData.new()
	tank.display_name = "Tank"
	tank.zombie_class = ZombieClassData.ZombieClass.TANK
	tank.base_health = 300.0
	tank.base_move_speed = 1.5
	tank.base_damage = 25.0
	tank.base_armor = 20.0
	tank.points_reward = 200
	tank.spawn_cost = 2
	tank.model_scale = 1.3
	tank.tint_color = Color(0.6, 0.6, 0.6)
	zombie_classes.append(tank)

	# Poison
	var poison = ZombieClassData.new()
	poison.display_name = "Poison Zombie"
	poison.zombie_class = ZombieClassData.ZombieClass.POISON
	poison.base_health = 80.0
	poison.base_move_speed = 3.0
	poison.base_damage = 12.0
	poison.points_reward = 150
	poison.spawn_cost = 1
	poison.has_poison = true
	poison.poison_damage_per_second = 10.0
	poison.tint_color = Color(0.5, 1.0, 0.5)
	poison.emission_color = Color(0.0, 1.0, 0.0)
	poison.emission_strength = 1.0
	zombie_classes.append(poison)

	# Exploder
	var exploder = ZombieClassData.new()
	exploder.display_name = "Exploder"
	exploder.zombie_class = ZombieClassData.ZombieClass.EXPLODER
	exploder.base_health = 50.0
	exploder.base_move_speed = 4.0
	exploder.base_damage = 5.0
	exploder.points_reward = 180
	exploder.spawn_cost = 1
	exploder.has_explosion = true
	exploder.explosion_damage = 60.0
	exploder.explosion_radius = 6.0
	exploder.tint_color = Color(1.0, 0.5, 0.0)
	exploder.emission_color = Color(1.0, 0.3, 0.0)
	exploder.emission_strength = 1.5
	zombie_classes.append(exploder)

	# Behemoth Boss
	var behemoth = ZombieClassData.new()
	behemoth.display_name = "Behemoth"
	behemoth.zombie_class = ZombieClassData.ZombieClass.BOSS_BEHEMOTH
	behemoth.base_health = 1000.0
	behemoth.base_move_speed = 2.0
	behemoth.base_damage = 50.0
	behemoth.base_armor = 50.0
	behemoth.points_reward = 1000
	behemoth.experience_reward = 500
	behemoth.spawn_cost = 5
	behemoth.is_boss = true
	behemoth.model_scale = 2.0
	behemoth.tint_color = Color(0.8, 0.2, 0.2)
	behemoth.guaranteed_drop = true
	behemoth.loot_multiplier = 3.0
	zombie_classes.append(behemoth)

func get_current_state() -> Dictionary:
	return {
		"wave": current_wave,
		"is_active": is_wave_active,
		"is_intermission": is_intermission,
		"intermission_time": intermission_timer,
		"zombies_alive": zombies_alive,
		"zombies_remaining": get_zombies_remaining(),
		"zombies_killed": zombies_killed_this_wave,
		"total_killed": total_zombies_killed,
		"progress": get_wave_progress()
	}

# ============================================
# NETWORK REPLICATION
# ============================================

@rpc("any_peer", "reliable")
func _request_wave_state():
	"""Client requests current wave state"""
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	var state = get_current_state()
	_receive_wave_state.rpc_id(sender_id, state)

@rpc("authority", "reliable")
func _receive_wave_state(state: Dictionary):
	"""Receive full wave state from server"""
	current_wave = state.get("wave", 0)
	is_wave_active = state.get("is_active", false)
	is_intermission = state.get("is_intermission", false)
	intermission_timer = state.get("intermission_time", 0.0)
	zombies_alive = state.get("zombies_alive", 0)
	zombies_killed_this_wave = state.get("zombies_killed", 0)
	total_zombies_killed = state.get("total_killed", 0)

	print("Wave state received: Wave %d" % current_wave)

@rpc("authority", "reliable")
func _sync_wave_start(wave: int, zombie_count: int, is_boss: bool):
	"""Receive wave start from server"""
	if is_network_authority:
		return

	current_wave = wave
	is_wave_active = true
	is_intermission = false
	zombies_to_spawn = zombie_count
	zombies_spawned_this_wave = 0
	zombies_killed_this_wave = 0
	zombies_alive = 0

	wave_started.emit(wave, zombie_count)

	if is_boss:
		boss_wave.emit(wave)

	print("Wave %d started! (synced from server)" % wave)

@rpc("authority", "reliable")
func _sync_wave_complete(wave: int, kills: int):
	"""Receive wave complete from server"""
	if is_network_authority:
		return

	is_wave_active = false
	zombies_killed_this_wave = kills

	wave_completed.emit(wave)

	print("Wave %d complete! (synced from server)" % wave)

@rpc("authority", "reliable")
func _sync_intermission_start(duration: float):
	"""Receive intermission start from server"""
	if is_network_authority:
		return

	is_intermission = true
	intermission_timer = duration

	intermission_started.emit(duration)

@rpc("authority", "reliable")
func _sync_intermission_end():
	"""Receive intermission end from server"""
	if is_network_authority:
		return

	is_intermission = false

	intermission_ended.emit()

@rpc("authority", "unreliable_ordered")
func _sync_zombie_count(alive: int, killed: int):
	"""Receive zombie count update from server"""
	if is_network_authority:
		return

	zombies_alive = alive
	zombies_killed_this_wave = killed

func sync_zombie_counts():
	"""Server syncs zombie counts to clients"""
	if is_network_authority and multiplayer.has_multiplayer_peer():
		_sync_zombie_count.rpc(zombies_alive, zombies_killed_this_wave)

# ============================================
# BACKEND INTEGRATION
# ============================================

func _sync_wave_to_backend():
	"""Sync wave state to backend"""
	if not backend or not backend.is_authenticated:
		return

	var state = get_current_state()

	# Update server info with wave data
	if websocket_hub and websocket_hub.has_method("update_server_info"):
		websocket_hub.update_server_info({
			"currentWave": current_wave,
			"isActive": is_wave_active
		})

func _on_backend_wave_update(state: Dictionary):
	"""Handle wave state from backend (for spectators/late joiners)"""
	if is_network_authority:
		return

	current_wave = state.get("currentWave", current_wave)
	is_wave_active = state.get("isActive", is_wave_active)
