extends Node
class_name PerformanceOptimizer

# Performance optimization manager
# Handles LOD, culling, update frequency management, and performance monitoring

signal performance_warning(message: String, severity: int)
signal quality_level_changed(new_level: int)

enum QualityLevel {
	LOW = 0,
	MEDIUM = 1,
	HIGH = 2,
	ULTRA = 3
}

# Current quality settings
var current_quality: QualityLevel = QualityLevel.HIGH
var auto_adjust_quality: bool = true

# Performance thresholds
var target_fps: float = 60.0
var min_acceptable_fps: float = 30.0
var performance_sample_rate: float = 1.0

# Update frequency management
var update_groups: Dictionary = {}  # group_name -> UpdateGroupData
var frame_budget_ms: float = 16.67  # Target ~60fps

# LOD settings
var lod_distances: Array = [20.0, 50.0, 100.0, 200.0]  # LOD switch distances

# Culling
var frustum_culling_enabled: bool = true
var occlusion_culling_enabled: bool = true
var distance_culling_threshold: float = 150.0

# Stats
var current_fps: float = 0.0
var avg_fps: float = 0.0
var fps_samples: Array = []
var max_fps_samples: int = 60

class UpdateGroupData:
	var nodes: Array = []
	var update_interval: float = 0.016  # Default 60fps
	var last_update_time: float = 0.0
	var priority: int = 0
	var enabled: bool = true

func _ready():
	add_to_group("performance_optimizer")

	# Setup default update groups
	_setup_update_groups()

	# Start performance monitoring
	set_process(true)

func _setup_update_groups():
	"""Create default update groups with different frequencies"""
	# Critical updates - every frame
	create_update_group("critical", 0.0, 0)

	# Fast updates - 60fps
	create_update_group("fast", 0.016, 1)

	# Normal updates - 30fps
	create_update_group("normal", 0.033, 2)

	# Slow updates - 15fps
	create_update_group("slow", 0.066, 3)

	# Very slow updates - 5fps (for distant/non-critical)
	create_update_group("background", 0.2, 4)

func _process(delta):
	# Track FPS
	current_fps = 1.0 / delta if delta > 0 else 0
	fps_samples.append(current_fps)
	if fps_samples.size() > max_fps_samples:
		fps_samples.pop_front()

	avg_fps = 0
	for fps in fps_samples:
		avg_fps += fps
	avg_fps /= fps_samples.size()

	# Auto-adjust quality
	if auto_adjust_quality:
		_auto_adjust_quality()

	# Process update groups
	_process_update_groups(delta)

func _auto_adjust_quality():
	"""Automatically adjust quality based on performance"""
	if avg_fps < min_acceptable_fps and current_quality > QualityLevel.LOW:
		set_quality_level(current_quality - 1)
		performance_warning.emit("Performance low, reducing quality", 1)
	elif avg_fps > target_fps * 1.2 and current_quality < QualityLevel.ULTRA:
		# Only increase if consistently good
		if fps_samples.size() >= max_fps_samples:
			var min_fps = fps_samples.min()
			if min_fps > target_fps:
				set_quality_level(current_quality + 1)

func _process_update_groups(delta):
	"""Process registered update groups at their intervals"""
	var current_time = Time.get_ticks_msec() / 1000.0

	for group_name in update_groups:
		var group = update_groups[group_name] as UpdateGroupData
		if not group.enabled:
			continue

		var elapsed = current_time - group.last_update_time
		if elapsed >= group.update_interval:
			group.last_update_time = current_time
			_update_group_nodes(group)

func _update_group_nodes(group: UpdateGroupData):
	"""Update all nodes in a group"""
	for node in group.nodes:
		if is_instance_valid(node) and node.has_method("optimized_update"):
			node.optimized_update()

# ============================================
# UPDATE GROUP MANAGEMENT
# ============================================

func create_update_group(group_name: String, interval: float, priority: int = 0):
	"""Create a new update group"""
	var group = UpdateGroupData.new()
	group.update_interval = interval
	group.priority = priority
	group.last_update_time = Time.get_ticks_msec() / 1000.0
	update_groups[group_name] = group

func register_node(node: Node, group_name: String):
	"""Register a node to an update group"""
	if not update_groups.has(group_name):
		push_warning("Update group '%s' not found" % group_name)
		return

	var group = update_groups[group_name] as UpdateGroupData
	if node not in group.nodes:
		group.nodes.append(node)

func unregister_node(node: Node, group_name: String = ""):
	"""Unregister a node from update groups"""
	if group_name != "":
		if update_groups.has(group_name):
			update_groups[group_name].nodes.erase(node)
	else:
		# Remove from all groups
		for gn in update_groups:
			update_groups[gn].nodes.erase(node)

func set_group_interval(group_name: String, interval: float):
	"""Set update interval for a group"""
	if update_groups.has(group_name):
		update_groups[group_name].update_interval = interval

func enable_group(group_name: String, enabled: bool):
	"""Enable or disable an update group"""
	if update_groups.has(group_name):
		update_groups[group_name].enabled = enabled

# ============================================
# QUALITY SETTINGS
# ============================================

func set_quality_level(level: int):
	"""Set overall quality level"""
	level = clampi(level, 0, QualityLevel.ULTRA)
	if level == current_quality:
		return

	current_quality = level
	_apply_quality_settings()
	quality_level_changed.emit(current_quality)

func _apply_quality_settings():
	"""Apply quality settings based on current level"""
	match current_quality:
		QualityLevel.LOW:
			_apply_low_quality()
		QualityLevel.MEDIUM:
			_apply_medium_quality()
		QualityLevel.HIGH:
			_apply_high_quality()
		QualityLevel.ULTRA:
			_apply_ultra_quality()

func _apply_low_quality():
	"""Apply low quality settings"""
	# Reduce shadow quality
	RenderingServer.directional_shadow_atlas_set_size(1024, true)

	# Reduce update frequencies
	set_group_interval("normal", 0.066)  # 15fps
	set_group_interval("slow", 0.133)    # ~7fps
	set_group_interval("background", 0.5) # 2fps

	# Increase LOD distances (more aggressive)
	lod_distances = [10.0, 25.0, 50.0, 100.0]

	# Reduce culling distance
	distance_culling_threshold = 80.0

func _apply_medium_quality():
	"""Apply medium quality settings"""
	RenderingServer.directional_shadow_atlas_set_size(2048, true)

	set_group_interval("normal", 0.05)   # 20fps
	set_group_interval("slow", 0.1)      # 10fps
	set_group_interval("background", 0.25) # 4fps

	lod_distances = [15.0, 40.0, 80.0, 150.0]
	distance_culling_threshold = 120.0

func _apply_high_quality():
	"""Apply high quality settings"""
	RenderingServer.directional_shadow_atlas_set_size(4096, true)

	set_group_interval("normal", 0.033)  # 30fps
	set_group_interval("slow", 0.066)    # 15fps
	set_group_interval("background", 0.2) # 5fps

	lod_distances = [20.0, 50.0, 100.0, 200.0]
	distance_culling_threshold = 150.0

func _apply_ultra_quality():
	"""Apply ultra quality settings"""
	RenderingServer.directional_shadow_atlas_set_size(8192, true)

	set_group_interval("normal", 0.016)  # 60fps
	set_group_interval("slow", 0.033)    # 30fps
	set_group_interval("background", 0.1) # 10fps

	lod_distances = [30.0, 70.0, 140.0, 300.0]
	distance_culling_threshold = 200.0

# ============================================
# LOD MANAGEMENT
# ============================================

func get_lod_level(distance: float) -> int:
	"""Get LOD level based on distance from camera"""
	for i in range(lod_distances.size()):
		if distance < lod_distances[i]:
			return i
	return lod_distances.size()

func should_cull_by_distance(distance: float) -> bool:
	"""Check if object should be culled by distance"""
	return distance > distance_culling_threshold

func get_update_frequency_for_distance(distance: float) -> float:
	"""Get recommended update frequency based on distance"""
	if distance < lod_distances[0]:
		return 0.016  # 60fps
	elif distance < lod_distances[1]:
		return 0.033  # 30fps
	elif distance < lod_distances[2]:
		return 0.066  # 15fps
	else:
		return 0.2    # 5fps

# ============================================
# FRAME BUDGET
# ============================================

func can_afford_operation(estimated_ms: float) -> bool:
	"""Check if we can afford an operation within frame budget"""
	var current_frame_time = 1000.0 / current_fps if current_fps > 0 else frame_budget_ms
	var remaining_budget = frame_budget_ms - current_frame_time
	return remaining_budget > estimated_ms

func get_remaining_frame_budget() -> float:
	"""Get remaining frame budget in milliseconds"""
	var current_frame_time = 1000.0 / current_fps if current_fps > 0 else 0
	return max(0, frame_budget_ms - current_frame_time)

# ============================================
# STATS & DEBUG
# ============================================

func get_performance_stats() -> Dictionary:
	"""Get current performance statistics"""
	return {
		"current_fps": current_fps,
		"avg_fps": avg_fps,
		"min_fps": fps_samples.min() if fps_samples.size() > 0 else 0,
		"max_fps": fps_samples.max() if fps_samples.size() > 0 else 0,
		"quality_level": current_quality,
		"frame_budget_remaining": get_remaining_frame_budget(),
		"update_groups": _get_group_stats()
	}

func _get_group_stats() -> Dictionary:
	"""Get statistics for all update groups"""
	var stats = {}
	for group_name in update_groups:
		var group = update_groups[group_name]
		stats[group_name] = {
			"node_count": group.nodes.size(),
			"interval": group.update_interval,
			"enabled": group.enabled
		}
	return stats

func print_performance_stats():
	"""Print performance stats to console"""
	var stats = get_performance_stats()
	print("=== Performance Stats ===")
	print("FPS: %.1f (avg: %.1f, min: %.1f, max: %.1f)" % [
		stats.current_fps, stats.avg_fps, stats.min_fps, stats.max_fps
	])
	print("Quality Level: %d" % stats.quality_level)
	print("Frame Budget Remaining: %.2fms" % stats.frame_budget_remaining)
	print("Update Groups:")
	for group_name in stats.update_groups:
		var g = stats.update_groups[group_name]
		print("  %s: %d nodes, %.3fs interval" % [group_name, g.node_count, g.interval])

# ============================================
# UTILITY
# ============================================

func optimize_scene(scene_root: Node):
	"""Apply optimizations to a scene"""
	# Find and register nodes for optimized updates
	_optimize_node_recursive(scene_root)

func _optimize_node_recursive(node: Node):
	"""Recursively optimize nodes in scene"""
	# Zombies go to normal update group
	if node.is_in_group("zombies"):
		register_node(node, "normal")

	# Loot items go to slow update group
	elif node.is_in_group("loot"):
		register_node(node, "slow")

	# VFX go to fast update group
	elif node.is_in_group("vfx"):
		register_node(node, "fast")

	# Process children
	for child in node.get_children():
		_optimize_node_recursive(child)
