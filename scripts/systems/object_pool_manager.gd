extends Node
class_name ObjectPoolManager

# High-performance object pooling system
# Reduces garbage collection and allocation overhead
# Supports multiple pool types with configurable sizes

signal pool_created(pool_name: String)
signal pool_exhausted(pool_name: String)
signal object_recycled(pool_name: String)

# Pool configuration
var pools: Dictionary = {}  # pool_name -> PoolData
var pool_configs: Dictionary = {}  # pool_name -> PoolConfig

# Stats for debugging
var stats: Dictionary = {
	"total_allocations": 0,
	"total_recycles": 0,
	"cache_hits": 0,
	"cache_misses": 0
}

class PoolConfig:
	var scene_path: String = ""
	var packed_scene: PackedScene = null
	var initial_size: int = 10
	var max_size: int = 100
	var grow_size: int = 5
	var auto_grow: bool = true
	var recycle_callback: Callable  # Optional callback when recycling

class PoolData:
	var available: Array = []
	var in_use: Array = []
	var config: PoolConfig

func _ready():
	add_to_group("object_pool")

	# Pre-configure common pools
	_setup_default_pools()

func _setup_default_pools():
	"""Setup commonly used object pools"""
	# Zombie pool - use correct path
	register_pool("zombie", "res://scenes/zombies/zombie.tscn", 20, 100)

	# Projectile pools
	register_pool("acid_projectile", "res://scenes/projectiles/acid_projectile.tscn", 10, 50)

	# Loot item pool
	register_pool("loot_item", "res://scenes/items/loot_item.tscn", 20, 100)

	# Pickup pools
	register_pool("ammo_pickup", "res://scenes/items/ammo_pickup.tscn", 10, 50)
	register_pool("health_pickup", "res://scenes/items/health_pickup.tscn", 10, 50)

func register_pool(pool_name: String, scene_path: String, initial_size: int = 10, max_size: int = 100, grow_size: int = 5):
	"""Register a new object pool"""
	if pools.has(pool_name):
		push_warning("Pool '%s' already exists" % pool_name)
		return

	var config = PoolConfig.new()
	config.scene_path = scene_path
	config.initial_size = initial_size
	config.max_size = max_size
	config.grow_size = grow_size
	config.auto_grow = true

	# Try to load the scene
	if ResourceLoader.exists(scene_path):
		config.packed_scene = load(scene_path)
	else:
		push_warning("Scene not found for pool '%s': %s" % [pool_name, scene_path])
		return

	pool_configs[pool_name] = config

	# Create pool data
	var pool_data = PoolData.new()
	pool_data.config = config
	pools[pool_name] = pool_data

	# Pre-populate pool
	_grow_pool(pool_name, initial_size)

	pool_created.emit(pool_name)

func register_pool_with_scene(pool_name: String, scene: PackedScene, initial_size: int = 10, max_size: int = 100):
	"""Register a pool with an already loaded PackedScene"""
	if pools.has(pool_name):
		return

	var config = PoolConfig.new()
	config.packed_scene = scene
	config.initial_size = initial_size
	config.max_size = max_size
	config.grow_size = 5
	config.auto_grow = true

	pool_configs[pool_name] = config

	var pool_data = PoolData.new()
	pool_data.config = config
	pools[pool_name] = pool_data

	_grow_pool(pool_name, initial_size)
	pool_created.emit(pool_name)

func _grow_pool(pool_name: String, count: int):
	"""Add more objects to a pool"""
	var pool = pools.get(pool_name) as PoolData
	if not pool:
		return

	var config = pool.config
	var current_total = pool.available.size() + pool.in_use.size()

	for i in range(count):
		if current_total + i >= config.max_size:
			break

		var instance = config.packed_scene.instantiate()
		_prepare_pooled_object(instance)
		pool.available.append(instance)
		stats.total_allocations += 1

func _prepare_pooled_object(obj: Node):
	"""Prepare object for pooling (disable and hide)"""
	if obj is Node3D:
		obj.visible = false
		obj.process_mode = Node.PROCESS_MODE_DISABLED
	elif obj is Node2D:
		obj.visible = false
		obj.process_mode = Node.PROCESS_MODE_DISABLED

	# Add to holding container
	if not obj.is_inside_tree():
		add_child(obj)

func acquire(pool_name: String) -> Node:
	"""Get an object from the pool"""
	var pool = pools.get(pool_name) as PoolData
	if not pool:
		stats.cache_misses += 1
		push_warning("Pool '%s' not found" % pool_name)
		return null

	var obj: Node = null

	if pool.available.size() > 0:
		obj = pool.available.pop_back()
		stats.cache_hits += 1
	else:
		# Pool exhausted
		if pool.config.auto_grow:
			var grow_amount = min(pool.config.grow_size, pool.config.max_size - pool.available.size() - pool.in_use.size())
			if grow_amount > 0:
				_grow_pool(pool_name, grow_amount)
				if pool.available.size() > 0:
					obj = pool.available.pop_back()
					stats.cache_hits += 1

		if not obj:
			stats.cache_misses += 1
			pool_exhausted.emit(pool_name)

			# Emergency allocation if pool is full
			if pool.config.packed_scene:
				obj = pool.config.packed_scene.instantiate()
				stats.total_allocations += 1

	if obj:
		pool.in_use.append(obj)
		_activate_pooled_object(obj)

	return obj

func _activate_pooled_object(obj: Node):
	"""Activate a pooled object for use"""
	if obj is Node3D:
		obj.visible = true
		obj.process_mode = Node.PROCESS_MODE_INHERIT
	elif obj is Node2D:
		obj.visible = true
		obj.process_mode = Node.PROCESS_MODE_INHERIT

	# Reset common properties
	if obj is CharacterBody3D:
		obj.velocity = Vector3.ZERO
	elif obj is RigidBody3D:
		obj.linear_velocity = Vector3.ZERO
		obj.angular_velocity = Vector3.ZERO

func release(pool_name: String, obj: Node):
	"""Return an object to the pool"""
	var pool = pools.get(pool_name) as PoolData
	if not pool:
		# Object doesn't belong to any pool, just free it
		obj.queue_free()
		return

	# Remove from in_use
	var idx = pool.in_use.find(obj)
	if idx >= 0:
		pool.in_use.remove_at(idx)

	# Reset and return to available
	_reset_pooled_object(obj)
	pool.available.append(obj)

	stats.total_recycles += 1
	object_recycled.emit(pool_name)

func _reset_pooled_object(obj: Node):
	"""Reset object state for reuse"""
	# Deactivate
	if obj is Node3D:
		obj.visible = false
		obj.process_mode = Node.PROCESS_MODE_DISABLED
	elif obj is Node2D:
		obj.visible = false
		obj.process_mode = Node.PROCESS_MODE_DISABLED

	# Reparent to pool manager
	if obj.get_parent() != self:
		if obj.get_parent():
			obj.get_parent().remove_child(obj)
		add_child(obj)

	# Reset transform
	if obj is Node3D:
		obj.global_position = Vector3.ZERO
		obj.rotation = Vector3.ZERO
		obj.scale = Vector3.ONE

	# Call custom reset if available
	if obj.has_method("reset_for_pool"):
		obj.reset_for_pool()

func clear_pool(pool_name: String):
	"""Clear all objects in a pool"""
	var pool = pools.get(pool_name) as PoolData
	if not pool:
		return

	for obj in pool.available:
		if is_instance_valid(obj):
			obj.queue_free()
	pool.available.clear()

	for obj in pool.in_use:
		if is_instance_valid(obj):
			obj.queue_free()
	pool.in_use.clear()

func clear_all_pools():
	"""Clear all pools"""
	for pool_name in pools.keys():
		clear_pool(pool_name)

func get_pool_stats(pool_name: String) -> Dictionary:
	"""Get statistics for a specific pool"""
	var pool = pools.get(pool_name) as PoolData
	if not pool:
		return {}

	return {
		"available": pool.available.size(),
		"in_use": pool.in_use.size(),
		"total": pool.available.size() + pool.in_use.size(),
		"max_size": pool.config.max_size
	}

func get_all_stats() -> Dictionary:
	"""Get overall pool statistics"""
	var pool_stats = {}
	for pool_name in pools.keys():
		pool_stats[pool_name] = get_pool_stats(pool_name)

	return {
		"pools": pool_stats,
		"global": stats.duplicate()
	}

func print_stats():
	"""Print pool statistics to console"""
	print("=== Object Pool Statistics ===")
	print("Total Allocations: %d" % stats.total_allocations)
	print("Total Recycles: %d" % stats.total_recycles)
	print("Cache Hits: %d" % stats.cache_hits)
	print("Cache Misses: %d" % stats.cache_misses)
	print("")

	for pool_name in pools.keys():
		var s = get_pool_stats(pool_name)
		print("%s: %d available, %d in use, %d/%d total" % [
			pool_name, s.available, s.in_use, s.total, s.max_size
		])

# ============================================
# CONVENIENCE METHODS
# ============================================

func spawn_zombie(position: Vector3, parent: Node = null) -> Node:
	"""Spawn a zombie from the pool"""
	var zombie = acquire("zombie")
	if zombie:
		if parent:
			if zombie.get_parent() != parent:
				if zombie.get_parent():
					zombie.get_parent().remove_child(zombie)
				parent.add_child(zombie)
		zombie.global_position = position
	return zombie

func spawn_projectile(pool_name: String, position: Vector3, direction: Vector3, parent: Node = null) -> Node:
	"""Spawn a projectile from the pool"""
	var proj = acquire(pool_name)
	if proj:
		if parent:
			if proj.get_parent() != parent:
				if proj.get_parent():
					proj.get_parent().remove_child(proj)
				parent.add_child(proj)
		proj.global_position = position
		if proj.has_method("launch"):
			proj.launch(direction)
	return proj

func spawn_loot(position: Vector3, item_data: Resource = null, parent: Node = null) -> Node:
	"""Spawn a loot item from the pool"""
	var loot = acquire("loot_item")
	if loot:
		if parent:
			if loot.get_parent() != parent:
				if loot.get_parent():
					loot.get_parent().remove_child(loot)
				parent.add_child(loot)
		loot.global_position = position
		if item_data and loot.has_method("set_item_data"):
			loot.set_item_data(item_data)
	return loot

func spawn_vfx(effect_name: String, position: Vector3, parent: Node = null) -> Node:
	"""Spawn a VFX from the pool"""
	var vfx = acquire(effect_name)
	if vfx:
		if parent:
			if vfx.get_parent() != parent:
				if vfx.get_parent():
					vfx.get_parent().remove_child(vfx)
				parent.add_child(vfx)
		vfx.global_position = position
		if vfx.has_method("play"):
			vfx.play()
	return vfx
