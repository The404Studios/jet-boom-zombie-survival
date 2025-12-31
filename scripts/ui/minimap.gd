extends Control
class_name Minimap

# Radar-style minimap showing nearby entities
# Rotates with player for compass-style navigation

signal marker_clicked(marker_type: String, position: Vector3)

# Map settings
@export var map_size: float = 150.0  # Size of minimap in pixels
@export var world_range: float = 50.0  # World units shown on map
@export var rotation_enabled: bool = true  # Rotate map with player
@export var zoom_level: float = 1.0

# Colors
@export var background_color: Color = Color(0.1, 0.1, 0.15, 0.8)
@export var border_color: Color = Color(0.3, 0.4, 0.5)
@export var player_color: Color = Color(0.3, 1, 0.3)
@export var teammate_color: Color = Color(0.3, 0.7, 1)
@export var enemy_color: Color = Color(1, 0.3, 0.3)
@export var objective_color: Color = Color(1, 0.8, 0)
@export var item_color: Color = Color(0.8, 0.8, 0.5)

# Marker sizes
@export var player_marker_size: float = 8.0
@export var entity_marker_size: float = 6.0
@export var objective_marker_size: float = 10.0

# UI References
var map_container: Control
var markers_container: Control
var player_marker: Control
var compass_labels: Dictionary = {}  # Direction -> Label

# Entity tracking
var tracked_entities: Dictionary = {}  # entity -> marker
var local_player: Node3D = null
var local_peer_id: int = 1

# Marker types
enum MarkerType {
	PLAYER,
	TEAMMATE,
	ENEMY,
	OBJECTIVE,
	ITEM,
	SPAWN,
	SIGIL
}

func _ready():
	# Set size
	custom_minimum_size = Vector2(map_size, map_size)
	size = Vector2(map_size, map_size)

	# Create UI structure
	_create_map_ui()

	# Get local peer ID
	if multiplayer.has_multiplayer_peer():
		local_peer_id = multiplayer.get_unique_id()

	# Find local player
	call_deferred("_find_local_player")

func _create_map_ui():
	# Background circle/radar
	map_container = Control.new()
	map_container.name = "MapContainer"
	map_container.set_anchors_preset(PRESET_FULL_RECT)
	map_container.clip_contents = true
	add_child(map_container)

	# Markers container (rotates with player)
	markers_container = Control.new()
	markers_container.name = "MarkersContainer"
	markers_container.set_anchors_preset(PRESET_CENTER)
	markers_container.size = Vector2(map_size * 2, map_size * 2)
	markers_container.position = -markers_container.size / 2
	map_container.add_child(markers_container)

	# Player marker (always centered)
	player_marker = _create_player_arrow()
	player_marker.position = Vector2(map_size / 2, map_size / 2)
	add_child(player_marker)

	# Compass directions
	_create_compass()

	# Redraw on ready
	queue_redraw()

func _draw():
	# Draw background circle
	var center = Vector2(map_size / 2, map_size / 2)
	var radius = map_size / 2 - 2

	# Background
	draw_circle(center, radius, background_color)

	# Border
	draw_arc(center, radius, 0, TAU, 64, border_color, 2.0)

	# Range rings
	var ring_color = Color(0.3, 0.3, 0.4, 0.3)
	draw_arc(center, radius * 0.5, 0, TAU, 32, ring_color, 1.0)
	draw_arc(center, radius * 0.25, 0, TAU, 16, ring_color, 1.0)

	# Center crosshair
	var cross_size = 4
	var cross_color = Color(0.5, 0.5, 0.6, 0.5)
	draw_line(center - Vector2(cross_size, 0), center + Vector2(cross_size, 0), cross_color, 1.0)
	draw_line(center - Vector2(0, cross_size), center + Vector2(0, cross_size), cross_color, 1.0)

func _create_player_arrow() -> Control:
	var arrow = Control.new()
	arrow.custom_minimum_size = Vector2(player_marker_size * 2, player_marker_size * 2)

	# Arrow will be drawn in _draw of parent or as separate polygon
	var polygon = Polygon2D.new()
	polygon.polygon = PackedVector2Array([
		Vector2(0, -player_marker_size),  # Top (forward)
		Vector2(-player_marker_size * 0.6, player_marker_size * 0.5),  # Bottom left
		Vector2(0, player_marker_size * 0.2),  # Center indent
		Vector2(player_marker_size * 0.6, player_marker_size * 0.5)  # Bottom right
	])
	polygon.color = player_color
	polygon.position = Vector2(player_marker_size, player_marker_size)
	arrow.add_child(polygon)

	return arrow

func _create_compass():
	var directions = {
		"N": 0,
		"E": 90,
		"S": 180,
		"W": 270
	}

	var radius = map_size / 2 - 12
	var center = Vector2(map_size / 2, map_size / 2)

	for dir in directions:
		var label = Label.new()
		label.text = dir
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		var angle = deg_to_rad(directions[dir] - 90)  # Offset so N is up
		var pos = center + Vector2(cos(angle), sin(angle)) * radius
		label.position = pos - Vector2(8, 8)

		compass_labels[dir] = label
		add_child(label)

func _process(_delta):
	if not local_player or not is_instance_valid(local_player):
		_find_local_player()
		return

	_update_entities()
	_update_markers()
	_update_compass()

func _find_local_player():
	# Try to find the local player
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.get("peer_id") == local_peer_id or (p.get("is_local_player") if p.has("is_local_player") else false):
			local_player = p
			return

	# Fallback - just get first player
	if players.size() > 0:
		local_player = players[0]

func _update_entities():
	# Scan for entities to track

	# Players
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player != local_player and is_instance_valid(player):
			var peer_id = player.get("peer_id") if player.has("peer_id") else 0
			if peer_id != local_peer_id:
				_ensure_marker(player, MarkerType.TEAMMATE)

	# Observed players (multiplayer)
	var observed = get_tree().get_nodes_in_group("observed_players")
	for obs_player in observed:
		if is_instance_valid(obs_player):
			_ensure_marker(obs_player, MarkerType.TEAMMATE)

	# Zombies
	var zombies = get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if is_instance_valid(zombie):
			_ensure_marker(zombie, MarkerType.ENEMY)

	# Objectives/sigils
	var sigils = get_tree().get_nodes_in_group("sigils")
	for sigil in sigils:
		if is_instance_valid(sigil):
			_ensure_marker(sigil, MarkerType.SIGIL)

	# Items
	var pickups = get_tree().get_nodes_in_group("pickups")
	for pickup in pickups:
		if is_instance_valid(pickup):
			_ensure_marker(pickup, MarkerType.ITEM)

	# Spawn points
	var spawns = get_tree().get_nodes_in_group("spawn_points")
	for spawn in spawns:
		if is_instance_valid(spawn):
			_ensure_marker(spawn, MarkerType.SPAWN)

	# Clean up invalid entities
	var to_remove = []
	for entity in tracked_entities:
		if not is_instance_valid(entity):
			to_remove.append(entity)

	for entity in to_remove:
		var marker = tracked_entities[entity]
		if is_instance_valid(marker):
			marker.queue_free()
		tracked_entities.erase(entity)

func _ensure_marker(entity: Node, type: MarkerType):
	if tracked_entities.has(entity):
		return

	var marker = _create_marker(type)
	markers_container.add_child(marker)
	tracked_entities[entity] = marker

func _create_marker(type: MarkerType) -> Control:
	var marker = Control.new()
	var size = entity_marker_size
	var color = enemy_color

	match type:
		MarkerType.TEAMMATE:
			color = teammate_color
		MarkerType.ENEMY:
			color = enemy_color
		MarkerType.OBJECTIVE, MarkerType.SIGIL:
			color = objective_color
			size = objective_marker_size
		MarkerType.ITEM:
			color = item_color
			size = entity_marker_size * 0.8
		MarkerType.SPAWN:
			color = Color(0.5, 0.5, 0.8, 0.5)
			size = entity_marker_size * 0.6

	marker.custom_minimum_size = Vector2(size * 2, size * 2)

	# Create visual
	var polygon = Polygon2D.new()

	match type:
		MarkerType.TEAMMATE:
			# Triangle pointing up
			polygon.polygon = PackedVector2Array([
				Vector2(0, -size),
				Vector2(-size * 0.7, size * 0.5),
				Vector2(size * 0.7, size * 0.5)
			])
		MarkerType.ENEMY:
			# Diamond
			polygon.polygon = PackedVector2Array([
				Vector2(0, -size),
				Vector2(size, 0),
				Vector2(0, size),
				Vector2(-size, 0)
			])
		MarkerType.OBJECTIVE, MarkerType.SIGIL:
			# Star-like
			var points = PackedVector2Array()
			for i in range(8):
				var angle = i * PI / 4
				var r = size if i % 2 == 0 else size * 0.5
				points.append(Vector2(cos(angle) * r, sin(angle) * r))
			polygon.polygon = points
		MarkerType.ITEM:
			# Small square
			polygon.polygon = PackedVector2Array([
				Vector2(-size * 0.5, -size * 0.5),
				Vector2(size * 0.5, -size * 0.5),
				Vector2(size * 0.5, size * 0.5),
				Vector2(-size * 0.5, size * 0.5)
			])
		MarkerType.SPAWN:
			# Circle approximation
			var points = PackedVector2Array()
			for i in range(8):
				var angle = i * TAU / 8
				points.append(Vector2(cos(angle) * size * 0.5, sin(angle) * size * 0.5))
			polygon.polygon = points

	polygon.color = color
	polygon.position = Vector2(size, size)
	marker.add_child(polygon)

	return marker

func _update_markers():
	if not local_player or not is_instance_valid(local_player):
		return

	var player_pos = local_player.global_position
	var player_rot = local_player.global_rotation.y if rotation_enabled else 0.0

	var center = Vector2(map_size, map_size)  # Center of markers_container
	var scale_factor = (map_size / 2) / (world_range / zoom_level)

	# Update marker positions
	for entity in tracked_entities:
		var marker = tracked_entities[entity]
		if not is_instance_valid(marker) or not is_instance_valid(entity):
			continue

		var entity_pos = entity.global_position if entity is Node3D else Vector3.ZERO

		# Calculate relative position
		var relative = entity_pos - player_pos
		var relative_2d = Vector2(relative.x, relative.z)

		# Rotate if player rotation is applied
		if rotation_enabled:
			relative_2d = relative_2d.rotated(-player_rot)

		# Scale to map
		var map_pos = center + relative_2d * scale_factor

		# Check if in range
		var distance = relative_2d.length()
		if distance > world_range / zoom_level:
			# Clamp to edge with arrow pointing outward
			var edge_pos = center + relative_2d.normalized() * (map_size / 2 - 10)
			marker.position = edge_pos - marker.custom_minimum_size / 2
			marker.modulate.a = 0.5  # Fade out edge markers
		else:
			marker.position = map_pos - marker.custom_minimum_size / 2
			marker.modulate.a = 1.0

		# Rotate enemy markers if rotating map
		if rotation_enabled and entity.is_in_group("zombies"):
			if entity is Node3D:
				marker.rotation = entity.global_rotation.y - player_rot

func _update_compass():
	if not local_player or not is_instance_valid(local_player):
		return

	if rotation_enabled:
		var player_rot = local_player.global_rotation.y

		var directions = {
			"N": 0,
			"E": PI / 2,
			"S": PI,
			"W": -PI / 2
		}

		var radius = map_size / 2 - 12
		var center = Vector2(map_size / 2, map_size / 2)

		for dir in compass_labels:
			var label = compass_labels[dir]
			var base_angle = directions[dir]
			var angle = base_angle - player_rot - PI / 2  # Adjust for up being north
			var pos = center + Vector2(cos(angle), sin(angle)) * radius
			label.position = pos - Vector2(8, 8)

# ============================================
# PUBLIC API
# ============================================

func set_zoom(level: float):
	"""Set zoom level (1.0 = default, 2.0 = zoomed in, 0.5 = zoomed out)"""
	zoom_level = clamp(level, 0.25, 4.0)

func zoom_in():
	set_zoom(zoom_level * 1.5)

func zoom_out():
	set_zoom(zoom_level / 1.5)

func set_rotation_enabled(enabled: bool):
	rotation_enabled = enabled

func set_range(new_range: float):
	"""Set world range shown on minimap"""
	world_range = clamp(new_range, 10.0, 200.0)

func add_custom_marker(world_position: Vector3, color: Color = Color.WHITE,
					   marker_name: String = "") -> int:
	"""Add a custom marker at world position. Returns marker ID."""
	var marker = Control.new()
	var size = entity_marker_size

	marker.custom_minimum_size = Vector2(size * 2, size * 2)
	marker.name = marker_name if not marker_name.is_empty() else "CustomMarker"

	var polygon = Polygon2D.new()
	polygon.polygon = PackedVector2Array([
		Vector2(0, -size),
		Vector2(size, 0),
		Vector2(0, size),
		Vector2(-size, 0)
	])
	polygon.color = color
	polygon.position = Vector2(size, size)
	marker.add_child(polygon)

	markers_container.add_child(marker)

	# Store position for update
	marker.set_meta("world_position", world_position)
	marker.set_meta("is_custom", true)

	return marker.get_instance_id()

func remove_custom_marker(marker_id: int):
	"""Remove a custom marker by ID"""
	for child in markers_container.get_children():
		if child.get_instance_id() == marker_id:
			child.queue_free()
			break

func clear_custom_markers():
	"""Remove all custom markers"""
	for child in markers_container.get_children():
		if child.has_meta("is_custom") and child.get_meta("is_custom"):
			child.queue_free()

func flash_marker(entity: Node, duration: float = 0.5):
	"""Flash a marker to draw attention"""
	if not tracked_entities.has(entity):
		return

	var marker = tracked_entities[entity]
	if not is_instance_valid(marker):
		return

	var tween = create_tween()
	tween.tween_property(marker, "modulate", Color(2, 2, 2), duration * 0.25)
	tween.tween_property(marker, "modulate", Color.WHITE, duration * 0.25)
	tween.set_loops(int(duration / 0.5))

func ping_location(world_position: Vector3, color: Color = Color.YELLOW):
	"""Create a temporary ping at location"""
	var marker_id = add_custom_marker(world_position, color, "Ping")

	# Find the marker and animate it
	for child in markers_container.get_children():
		if child.get_instance_id() == marker_id:
			# Pulse animation
			var tween = create_tween()
			tween.set_loops(4)
			tween.tween_property(child, "scale", Vector2(1.5, 1.5), 0.25)
			tween.tween_property(child, "scale", Vector2.ONE, 0.25)

			# Remove after animation
			await get_tree().create_timer(2.0).timeout
			if is_instance_valid(child):
				child.queue_free()
			break

# ============================================
# INPUT HANDLING
# ============================================

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_out()
