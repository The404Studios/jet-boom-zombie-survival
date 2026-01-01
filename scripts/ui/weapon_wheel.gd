extends Control
class_name WeaponWheel

# Radial weapon selection wheel
# Activated by holding a key, select by moving mouse

signal weapon_selected(slot: int)
signal wheel_opened
signal wheel_closed

# Settings
@export var wheel_radius: float = 150.0
@export var center_deadzone: float = 30.0
@export var segment_count: int = 8
@export var open_key: String = "weapon_wheel"

# Visual settings
@export var background_color: Color = Color(0, 0, 0, 0.7)
@export var segment_color: Color = Color(0.2, 0.2, 0.25, 0.9)
@export var highlight_color: Color = Color(0.3, 0.5, 0.8, 0.9)
@export var empty_color: Color = Color(0.15, 0.15, 0.18, 0.6)

# State
var is_open: bool = false
var selected_segment: int = -1
var weapons: Array = []  # Array of weapon data
var center_position: Vector2

# UI elements
var segments: Array = []  # Polygon2D for each segment
var icons: Array = []  # TextureRect for weapon icons
var labels: Array = []  # Label for weapon names
var ammo_labels: Array = []  # Label for ammo counts

# Player reference
var player: Node = null

func _ready():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Set to full screen
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Get center
	center_position = get_viewport_rect().size / 2

	# Create wheel UI
	_create_wheel()

	# Find player
	call_deferred("_find_player")

func _create_wheel():
	# Background overlay
	var bg = ColorRect.new()
	bg.color = background_color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Create segments
	var angle_per_segment = TAU / segment_count

	for i in range(segment_count):
		var start_angle = i * angle_per_segment - PI / 2 - angle_per_segment / 2
		var end_angle = start_angle + angle_per_segment

		# Create segment polygon
		var segment = Polygon2D.new()
		segment.polygon = _create_segment_polygon(start_angle, end_angle)
		segment.color = segment_color
		segment.position = center_position
		add_child(segment)
		segments.append(segment)

		# Create icon placeholder
		var icon_container = Control.new()
		var icon_angle = start_angle + angle_per_segment / 2
		var icon_distance = wheel_radius * 0.65
		icon_container.position = center_position + Vector2(cos(icon_angle), sin(icon_angle)) * icon_distance
		icon_container.position -= Vector2(24, 24)  # Center the icon
		add_child(icon_container)

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(48, 48)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_container.add_child(icon)
		icons.append(icon)

		# Create weapon name label
		var label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color.WHITE)
		var label_distance = wheel_radius * 0.9
		label.position = center_position + Vector2(cos(icon_angle), sin(icon_angle)) * label_distance
		label.position -= Vector2(50, 8)
		label.custom_minimum_size = Vector2(100, 20)
		add_child(label)
		labels.append(label)

		# Create ammo label
		var ammo = Label.new()
		ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ammo.add_theme_font_size_override("font_size", 10)
		ammo.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		ammo.position = label.position + Vector2(0, 14)
		ammo.custom_minimum_size = Vector2(100, 16)
		add_child(ammo)
		ammo_labels.append(ammo)

	# Create center circle
	var center = Polygon2D.new()
	center.polygon = _create_circle_polygon(center_deadzone, 16)
	center.color = Color(0.1, 0.1, 0.12, 0.9)
	center.position = center_position
	add_child(center)

	# Center label
	var center_label = Label.new()
	center_label.name = "CenterLabel"
	center_label.text = "CANCEL"
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 14)
	center_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	center_label.position = center_position - Vector2(40, 10)
	center_label.custom_minimum_size = Vector2(80, 20)
	add_child(center_label)

	# Slot number hints
	for i in range(segment_count):
		var hint = Label.new()
		hint.text = str(i + 1) if i < 9 else "0" if i == 9 else ""
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		var angle = i * (TAU / segment_count) - PI / 2
		var pos = center_position + Vector2(cos(angle), sin(angle)) * (wheel_radius + 15)
		hint.position = pos - Vector2(5, 8)
		add_child(hint)

func _create_segment_polygon(start_angle: float, end_angle: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var segments_per_arc = 8

	# Inner arc
	for i in range(segments_per_arc + 1):
		var angle = lerp(start_angle, end_angle, float(i) / segments_per_arc)
		points.append(Vector2(cos(angle), sin(angle)) * center_deadzone)

	# Outer arc (reversed)
	for i in range(segments_per_arc, -1, -1):
		var angle = lerp(start_angle, end_angle, float(i) / segments_per_arc)
		points.append(Vector2(cos(angle), sin(angle)) * wheel_radius)

	return points

func _create_circle_polygon(radius: float, segments_count: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments_count):
		var angle = i * TAU / segments_count
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		_update_weapons()

func _input(event):
	# Check for open/close
	if event.is_action_pressed(open_key):
		open_wheel()
	elif event.is_action_released(open_key):
		close_wheel()

	# Handle mouse movement when open
	if is_open and event is InputEventMouseMotion:
		_update_selection()

func _process(_delta):
	if is_open:
		_update_selection()

func open_wheel():
	if is_open:
		return

	is_open = true
	visible = true
	selected_segment = -1

	# Update weapon data
	_update_weapons()

	# Show mouse cursor and center it
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(center_position)

	# Slow down time slightly for dramatic effect
	Engine.time_scale = 0.3

	wheel_opened.emit()

func close_wheel():
	if not is_open:
		return

	is_open = false
	visible = false

	# Restore time
	Engine.time_scale = 1.0

	# Hide cursor
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Select weapon if valid segment
	if selected_segment >= 0 and selected_segment < weapons.size():
		if weapons[selected_segment] != null:
			weapon_selected.emit(selected_segment)
			_select_weapon(selected_segment)

	wheel_closed.emit()

func _update_selection():
	var mouse_pos = get_global_mouse_position()
	var relative = mouse_pos - center_position
	var distance = relative.length()

	# Check if in center deadzone
	if distance < center_deadzone:
		_highlight_segment(-1)
		return

	# Calculate which segment
	var angle = relative.angle() + PI / 2 + (TAU / segment_count) / 2
	if angle < 0:
		angle += TAU
	if angle >= TAU:
		angle -= TAU

	var segment_index = int(angle / (TAU / segment_count)) % segment_count
	_highlight_segment(segment_index)

func _highlight_segment(index: int):
	if selected_segment == index:
		return

	# Reset previous
	if selected_segment >= 0 and selected_segment < segments.size():
		var has_weapon = selected_segment < weapons.size() and weapons[selected_segment] != null
		segments[selected_segment].color = segment_color if has_weapon else empty_color

	selected_segment = index

	# Highlight new
	if selected_segment >= 0 and selected_segment < segments.size():
		var has_weapon = selected_segment < weapons.size() and weapons[selected_segment] != null
		if has_weapon:
			segments[selected_segment].color = highlight_color

func _update_weapons():
	weapons.clear()

	if not player:
		return

	# Get weapons from player - prefer get_weapons method
	if player.has_method("get_weapons"):
		weapons = player.get_weapons()
	else:
		# Try alternative methods
		var inventory = null
		if player.has_node("Inventory"):
			inventory = player.get_node("Inventory")
		elif "inventory" in player:
			inventory = player.inventory

		if inventory and inventory.has_method("get_weapons"):
			weapons = inventory.get_weapons()
		elif "weapons" in player:
			weapons = player.weapons
		elif "equipped_weapons" in player:
			weapons = player.equipped_weapons
		else:
			# Create placeholder weapons
			for i in range(segment_count):
				weapons.append(null)

	# Get current weapon info from player
	var current_weapon_index = player.current_weapon_index if "current_weapon_index" in player else 0
	var player_ammo = {}
	if player.has_method("get_weapon_ammo"):
		player_ammo = player.get_weapon_ammo()

	# Update visuals
	for i in range(segment_count):
		var weapon = weapons[i] if i < weapons.size() else null

		if weapon:
			# Set icon
			if icons[i] and "icon" in weapon and weapon.icon:
				icons[i].texture = weapon.icon

			# Set name
			if labels[i]:
				labels[i].text = weapon.item_name if "item_name" in weapon else "Weapon"

			# Set ammo - use player's ammo state for current weapon
			if ammo_labels[i]:
				var ammo_text = ""
				if i == current_weapon_index and not player_ammo.is_empty():
					ammo_text = "%d / %d" % [player_ammo.get("current", 0), player_ammo.get("reserve", 0)]
				elif "magazine_size" in weapon:
					ammo_text = "%d" % weapon.magazine_size
				ammo_labels[i].text = ammo_text

			# Update segment color - highlight current weapon
			if segments[i]:
				if i == current_weapon_index:
					segments[i].color = Color(0.3, 0.6, 0.3, 0.9)  # Green for current
				else:
					segments[i].color = segment_color
		else:
			# Empty slot
			if icons[i]:
				icons[i].texture = null
			if labels[i]:
				labels[i].text = "Empty"
			if ammo_labels[i]:
				ammo_labels[i].text = ""
			if segments[i]:
				segments[i].color = empty_color

func _select_weapon(slot: int):
	if not player:
		return

	# Switch weapon on player
	if player.has_method("switch_weapon"):
		player.switch_weapon(slot)
	elif player.has_method("equip_weapon_slot"):
		player.equip_weapon_slot(slot)

func set_weapons(weapon_array: Array):
	"""Manually set weapons to display"""
	weapons = weapon_array
	_update_weapons()

func refresh():
	"""Refresh weapon data from player"""
	_update_weapons()
