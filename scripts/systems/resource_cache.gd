extends Node

# Resource caching system for optimized resource management
# Caches frequently used resources and manages memory usage

signal cache_updated

class CacheEntry:
	var resource: Resource
	var path: String
	var last_accessed: float
	var access_count: int = 0
	var memory_size: int = 0 # Approximate size in bytes

	func _init(res: Resource, res_path: String):
		resource = res
		path = res_path
		last_accessed = Time.get_unix_time_from_system()

const MAX_CACHE_SIZE_MB: int = 256
const MAX_CACHE_ENTRIES: int = 500
const CACHE_CLEANUP_INTERVAL: float = 30.0
const MIN_ACCESS_COUNT_TO_KEEP: int = 2

var cache: Dictionary = {} # path -> CacheEntry
var cache_size_bytes: int = 0
var cleanup_timer: float = 0.0

# Priority caching for common resources
var priority_paths: Array[String] = []

func _ready():
	# Add priority resources
	_setup_priority_resources()

	# Preload priority resources
	_preload_priority_resources()

func _process(delta):
	cleanup_timer += delta

	if cleanup_timer >= CACHE_CLEANUP_INTERVAL:
		cleanup_timer = 0.0
		_cleanup_old_entries()

func _setup_priority_resources():
	# Zombie resources
	priority_paths.append_array([
		"res://resources/zombies/shambler.tres",
		"res://resources/zombies/runner.tres",
		"res://resources/zombies/tank.tres",
		"res://resources/zombies/poison.tres"
	])

	# Common weapons
	priority_paths.append_array([
		"res://resources/weapons/pistol.tres",
		"res://resources/weapons/combat_knife.tres",
		"res://resources/weapons/ak47.tres"
	])

	# UI resources
	priority_paths.append_array([
		"res://scenes/ui/hud.tscn",
		"res://scenes/ui/inventory_ui.tscn"
	])

func _preload_priority_resources():
	for path in priority_paths:
		if ResourceLoader.exists(path):
			get_cached_resource(path)

func get_cached_resource(path: String) -> Resource:
	# Check if already cached
	if cache.has(path):
		var entry = cache[path]
		entry.last_accessed = Time.get_unix_time_from_system()
		entry.access_count += 1
		return entry.resource

	# Load and cache
	var resource = ResourceLoader.load(path)

	if resource:
		_add_to_cache(path, resource)

	return resource

func _add_to_cache(path: String, resource: Resource):
	# Create cache entry
	var entry = CacheEntry.new(resource, path)
	entry.memory_size = _estimate_resource_size(resource)

	# Check cache size limits
	while (cache_size_bytes + entry.memory_size) > (MAX_CACHE_SIZE_MB * 1024 * 1024) and cache.size() > 0:
		_remove_least_valuable_entry()

	# Add to cache
	cache[path] = entry
	cache_size_bytes += entry.memory_size

	cache_updated.emit()

func _remove_least_valuable_entry():
	if cache.is_empty():
		return

	var least_valuable_path = ""
	var least_valuable_score = INF

	for path in cache.keys():
		# Don't remove priority resources
		if path in priority_paths:
			continue

		var entry = cache[path]
		var score = _calculate_entry_value(entry)

		if score < least_valuable_score:
			least_valuable_score = score
			least_valuable_path = path

	if least_valuable_path != "":
		remove_from_cache(least_valuable_path)

func _calculate_entry_value(entry: CacheEntry) -> float:
	var current_time = Time.get_unix_time_from_system()
	var time_since_access = current_time - entry.last_accessed

	# Higher access count = higher value
	# Recent access = higher value
	# Smaller size = slightly higher value
	var value = float(entry.access_count) / max(time_since_access, 1.0)
	value *= (1.0 / max(entry.memory_size / 1024.0, 1.0)) # Normalize by KB

	return value

func remove_from_cache(path: String):
	if not cache.has(path):
		return

	var entry = cache[path]
	cache_size_bytes -= entry.memory_size
	cache.erase(path)

	cache_updated.emit()

func _cleanup_old_entries():
	var current_time = Time.get_unix_time_from_system()
	var paths_to_remove = []

	for path in cache.keys():
		# Don't remove priority resources
		if path in priority_paths:
			continue

		var entry = cache[path]
		var time_since_access = current_time - entry.last_accessed

		# Remove entries not accessed in 5 minutes with low access count
		if time_since_access > 300.0 and entry.access_count < MIN_ACCESS_COUNT_TO_KEEP:
			paths_to_remove.append(path)

	for path in paths_to_remove:
		remove_from_cache(path)

	if paths_to_remove.size() > 0:
		print("Cleaned up %d cache entries" % paths_to_remove.size())

func _estimate_resource_size(resource: Resource) -> int:
	# Rough estimation of resource memory usage
	var size = 1024 # Base overhead

	if resource is Texture2D:
		var tex = resource as Texture2D
		size += tex.get_width() * tex.get_height() * 4 # RGBA

	elif resource is PackedScene:
		size += 10240 # Estimate 10KB per scene

	elif resource is Script:
		size += 2048 # Estimate 2KB per script

	else:
		size += 4096 # Default estimate

	return size

# Public API

func clear_cache():
	cache.clear()
	cache_size_bytes = 0
	cache_updated.emit()
	print("Cache cleared")

func get_cache_stats() -> Dictionary:
	return {
		"entry_count": cache.size(),
		"size_bytes": cache_size_bytes,
		"size_mb": cache_size_bytes / (1024.0 * 1024.0),
		"max_size_mb": MAX_CACHE_SIZE_MB
	}

func preload_resource(path: String):
	get_cached_resource(path)

func preload_resources(paths: Array):
	for path in paths:
		preload_resource(path)

func is_cached(path: String) -> bool:
	return cache.has(path)

func get_cache_entry_info(path: String) -> Dictionary:
	if not cache.has(path):
		return {}

	var entry = cache[path]
	return {
		"path": entry.path,
		"last_accessed": entry.last_accessed,
		"access_count": entry.access_count,
		"memory_size": entry.memory_size
	}

func add_priority_resource(path: String):
	if path not in priority_paths:
		priority_paths.append(path)
		preload_resource(path)

func remove_priority_resource(path: String):
	priority_paths.erase(path)
