extends Node
# Note: Do not use class_name here - this script is an autoload singleton
# Access via: GarbageCollector (the autoload name)

# Automatic garbage collection and memory management system
# Handles cleanup of orphaned nodes, old loot, distant entities, etc.

signal gc_cycle_complete(freed_count: int)
signal memory_warning(current_mb: float, threshold_mb: float)

# Collection settings
var gc_interval: float = 30.0  # Seconds between GC cycles
var gc_timer: float = 0.0

# Thresholds
var max_loot_age: float = 300.0  # 5 minutes
var max_projectile_age: float = 10.0
var max_vfx_age: float = 5.0
var orphan_check_interval: float = 60.0

# Distance-based cleanup
var max_entity_distance: float = 200.0
var cleanup_check_radius: float = 150.0

# Memory thresholds (MB)
var memory_warning_threshold: float = 512.0
var memory_critical_threshold: float = 768.0

# Tracked objects
var tracked_loot: Array = []
var tracked_projectiles: Array = []
var tracked_vfx: Array = []
var tracked_zombies: Array = []

# Stats
var stats: Dictionary = {
	"total_freed": 0,
	"loot_freed": 0,
	"projectiles_freed": 0,
	"vfx_freed": 0,
	"zombies_freed": 0,
	"orphans_freed": 0,
	"last_gc_freed": 0,
	"last_gc_time": 0.0
}

var orphan_timer: float = 0.0

func _ready():
	add_to_group("garbage_collector")
	set_process(true)

func _process(delta):
	gc_timer += delta
	orphan_timer += delta

	# Run GC cycle
	if gc_timer >= gc_interval:
		gc_timer = 0.0
		run_gc_cycle()

	# Check for orphans less frequently
	if orphan_timer >= orphan_check_interval:
		orphan_timer = 0.0
		cleanup_orphaned_nodes()

	# Monitor memory
	_check_memory()

func run_gc_cycle():
	"""Run a full garbage collection cycle"""
	var start_time = Time.get_ticks_usec()
	var freed_count = 0

	# Cleanup old loot
	freed_count += cleanup_old_loot()

	# Cleanup old projectiles
	freed_count += cleanup_old_projectiles()

	# Cleanup old VFX
	freed_count += cleanup_old_vfx()

	# Cleanup distant/stuck zombies
	freed_count += cleanup_distant_zombies()

	# Cleanup orphaned nodes in scene tree
	freed_count += cleanup_orphaned_nodes()

	# Update stats
	stats.last_gc_freed = freed_count
	stats.total_freed += freed_count
	stats.last_gc_time = (Time.get_ticks_usec() - start_time) / 1000.0

	gc_cycle_complete.emit(freed_count)

func cleanup_old_loot() -> int:
	"""Clean up loot items that have exceeded their lifespan"""
	var freed = 0
	var current_time = Time.get_ticks_msec() / 1000.0

	# Get all loot items
	var loot_nodes = get_tree().get_nodes_in_group("loot")

	for loot in loot_nodes:
		if not is_instance_valid(loot):
			continue

		# Check age
		var spawn_time = loot.get_meta("spawn_time", current_time)
		var age = current_time - spawn_time

		if age > max_loot_age:
			# Check if any player is looking at it
			if not _is_being_looked_at(loot):
				_safe_free(loot)
				freed += 1

	stats.loot_freed += freed
	return freed

func cleanup_old_projectiles() -> int:
	"""Clean up old/stuck projectiles"""
	var freed = 0
	var current_time = Time.get_ticks_msec() / 1000.0

	# Get all projectiles
	var projectiles = get_tree().get_nodes_in_group("projectiles")

	for proj in projectiles:
		if not is_instance_valid(proj):
			continue

		var spawn_time = proj.get_meta("spawn_time", current_time)
		var age = current_time - spawn_time

		if age > max_projectile_age:
			_safe_free(proj)
			freed += 1

	stats.projectiles_freed += freed
	return freed

func cleanup_old_vfx() -> int:
	"""Clean up old VFX effects"""
	var freed = 0
	var current_time = Time.get_ticks_msec() / 1000.0

	# Get all VFX
	var vfx_nodes = get_tree().get_nodes_in_group("vfx")

	for vfx in vfx_nodes:
		if not is_instance_valid(vfx):
			continue

		var spawn_time = vfx.get_meta("spawn_time", current_time)
		var age = current_time - spawn_time

		if age > max_vfx_age:
			_safe_free(vfx)
			freed += 1

	stats.vfx_freed += freed
	return freed

func cleanup_distant_zombies() -> int:
	"""Clean up zombies that are too far from all players"""
	var freed = 0

	var zombies = get_tree().get_nodes_in_group("zombies")
	var players = get_tree().get_nodes_in_group("player")

	if players.size() == 0:
		return 0

	for zombie in zombies:
		if not is_instance_valid(zombie):
			continue

		# Check distance to all players
		var min_distance = INF
		for player in players:
			if is_instance_valid(player) and zombie is Node3D and player is Node3D:
				var dist = zombie.global_position.distance_to(player.global_position)
				min_distance = min(min_distance, dist)

		# If too far from all players, clean up
		if min_distance > max_entity_distance:
			# Check if zombie is stuck (not moving)
			if zombie.has_method("get_velocity"):
				var vel = zombie.get_velocity()
				if vel.length() < 0.1:
					_safe_free(zombie)
					freed += 1
			else:
				_safe_free(zombie)
				freed += 1

	stats.zombies_freed += freed
	return freed

func cleanup_orphaned_nodes() -> int:
	"""Clean up orphaned nodes (nodes without valid parents or that shouldn't exist)"""
	var freed = 0

	# Check for common orphan types
	var orphan_groups = ["projectiles", "vfx", "temp_objects"]

	for group_name in orphan_groups:
		var nodes = get_tree().get_nodes_in_group(group_name)

		for node in nodes:
			if not is_instance_valid(node):
				continue

			# Check if parent is valid
			var parent = node.get_parent()
			if not parent or not is_instance_valid(parent):
				_safe_free(node)
				freed += 1
				continue

			# Check if node is in valid state
			if node is Node3D:
				var pos = node.global_position
				# Cleanup nodes at extreme positions (likely bugs)
				if abs(pos.x) > 10000 or abs(pos.y) > 10000 or abs(pos.z) > 10000:
					_safe_free(node)
					freed += 1
					continue

	stats.orphans_freed += freed
	return freed

func _safe_free(node: Node):
	"""Safely free a node"""
	if not is_instance_valid(node):
		return

	# Try to return to pool first
	var pool_manager = get_node_or_null("/root/ObjectPoolManager")
	if pool_manager:
		# Determine pool name
		var pool_name = ""
		if node.is_in_group("zombies"):
			pool_name = "zombie"
		elif node.is_in_group("loot"):
			pool_name = "loot_item"
		elif node.is_in_group("projectiles"):
			pool_name = "bullet"
		elif node.is_in_group("vfx"):
			# Try to determine VFX type
			if "blood" in node.name.to_lower():
				pool_name = "blood_splat"
			elif "impact" in node.name.to_lower():
				pool_name = "impact_effect"

		if pool_name != "" and pool_manager.has_method("release"):
			pool_manager.release(pool_name, node)
			return

	# If not pooled, queue free
	node.queue_free()

func _is_being_looked_at(node: Node3D) -> bool:
	"""Check if any player is currently looking at a node"""
	if not is_instance_valid(node):
		return false

	var players = get_tree().get_nodes_in_group("player")

	for player in players:
		if not is_instance_valid(player):
			continue

		# Check if player has camera
		var camera = player.get_node_or_null("Camera3D")
		if not camera:
			continue

		# Check if node is in front of camera and close enough
		var to_node = node.global_position - camera.global_position
		var forward = -camera.global_transform.basis.z

		# Dot product check (in front)
		if forward.dot(to_node.normalized()) > 0.5:
			# Distance check
			if to_node.length() < 15.0:
				return true

	return false

func _check_memory():
	"""Check memory usage and emit warnings if needed"""
	var memory_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0

	if memory_mb > memory_critical_threshold:
		memory_warning.emit(memory_mb, memory_critical_threshold)
		# Force aggressive GC
		run_aggressive_gc()
	elif memory_mb > memory_warning_threshold:
		memory_warning.emit(memory_mb, memory_warning_threshold)

func run_aggressive_gc():
	"""Run aggressive garbage collection when memory is critical"""
	print("[GC] Running aggressive garbage collection...")

	# Reduce thresholds temporarily
	var old_loot_age = max_loot_age
	var old_projectile_age = max_projectile_age
	var old_vfx_age = max_vfx_age
	var old_entity_distance = max_entity_distance

	max_loot_age = 60.0
	max_projectile_age = 3.0
	max_vfx_age = 2.0
	max_entity_distance = 100.0

	# Run GC
	run_gc_cycle()

	# Restore thresholds
	max_loot_age = old_loot_age
	max_projectile_age = old_projectile_age
	max_vfx_age = old_vfx_age
	max_entity_distance = old_entity_distance

	print("[GC] Aggressive GC complete")

# ============================================
# TRACKING
# ============================================

func track_loot(node: Node):
	"""Track a loot item for garbage collection"""
	if node not in tracked_loot:
		tracked_loot.append(node)
		node.set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)

func track_projectile(node: Node):
	"""Track a projectile for garbage collection"""
	if node not in tracked_projectiles:
		tracked_projectiles.append(node)
		node.set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)

func track_vfx(node: Node):
	"""Track a VFX for garbage collection"""
	if node not in tracked_vfx:
		tracked_vfx.append(node)
		node.set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)

func untrack(node: Node):
	"""Stop tracking a node"""
	tracked_loot.erase(node)
	tracked_projectiles.erase(node)
	tracked_vfx.erase(node)
	tracked_zombies.erase(node)

# ============================================
# CONFIGURATION
# ============================================

func set_gc_interval(interval: float):
	"""Set garbage collection interval in seconds"""
	gc_interval = max(5.0, interval)

func set_loot_lifetime(seconds: float):
	"""Set maximum loot lifetime"""
	max_loot_age = max(60.0, seconds)

func set_entity_cleanup_distance(distance: float):
	"""Set distance for entity cleanup"""
	max_entity_distance = max(50.0, distance)

# ============================================
# STATS
# ============================================

func get_stats() -> Dictionary:
	"""Get garbage collection statistics"""
	return stats.duplicate()

func print_stats():
	"""Print GC stats to console"""
	print("=== Garbage Collector Stats ===")
	print("Total Freed: %d" % stats.total_freed)
	print("  Loot: %d" % stats.loot_freed)
	print("  Projectiles: %d" % stats.projectiles_freed)
	print("  VFX: %d" % stats.vfx_freed)
	print("  Zombies: %d" % stats.zombies_freed)
	print("  Orphans: %d" % stats.orphans_freed)
	print("Last GC: %d freed in %.2fms" % [stats.last_gc_freed, stats.last_gc_time])
	print("Memory: %.1f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))

func get_memory_usage() -> Dictionary:
	"""Get current memory usage"""
	return {
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}
