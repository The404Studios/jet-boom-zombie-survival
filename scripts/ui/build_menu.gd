extends Control
class_name BuildMenu

## Build menu UI for placing props and barricades
## Press B to open, shows available items with costs

signal item_selected(prop_type: int)
signal placement_started(prop_type: int)
signal placement_cancelled
signal placement_confirmed(prop_type: int, position: Vector3, rotation: Vector3)
signal menu_opened
signal menu_closed

enum BuildMode {
	NONE,
	SELECTING,
	PLACING,
	NAILING,
	REPAIRING
}

# UI References
@onready var menu_panel: Panel = $MenuPanel
@onready var items_container: GridContainer = $MenuPanel/ScrollContainer/ItemsGrid
@onready var preview_panel: Panel = $PreviewPanel
@onready var preview_name: Label = $PreviewPanel/VBox/Name
@onready var preview_cost: Label = $PreviewPanel/VBox/Cost
@onready var preview_hp: Label = $PreviewPanel/VBox/HP
@onready var preview_description: Label = $PreviewPanel/VBox/Description
@onready var status_label: Label = $StatusLabel
@onready var crosshair: Control = $Crosshair

# Placement preview
var placement_preview: Node3D = null
var placement_valid: bool = false
var placement_rotation: float = 0.0

# State
var build_mode: BuildMode = BuildMode.NONE
var selected_prop_type: int = -1
var player_points: int = 0
var prop_manager: Node = null
var camera: Camera3D = null

# Input
var rotate_speed: float = 90.0  # Degrees per second
var grid_snap: float = 0.5
var max_placement_distance: float = 5.0

# Colors
const COLOR_VALID: Color = Color(0.2, 1.0, 0.2, 0.5)
const COLOR_INVALID: Color = Color(1.0, 0.2, 0.2, 0.5)
const COLOR_SELECTED: Color = Color(0.4, 0.8, 1.0, 1.0)

func _ready():
	# Get references
	prop_manager = get_node_or_null("/root/PropManager")

	# Initial state
	visible = false
	if menu_panel:
		menu_panel.visible = false
	if preview_panel:
		preview_panel.visible = false
	if status_label:
		status_label.visible = false
	if crosshair:
		crosshair.visible = false

	# Create items
	_populate_build_menu()

func _process(delta):
	if build_mode == BuildMode.PLACING:
		_update_placement_preview(delta)

func _input(event):
	# Toggle build menu with B
	if event.is_action_pressed("build_menu"):
		if build_mode == BuildMode.NONE:
			open_menu()
		else:
			close_menu()
		return

	# Handle placement mode inputs
	if build_mode == BuildMode.PLACING:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("build_menu"):
			cancel_placement()
		elif event.is_action_pressed("attack") or event.is_action_pressed("ui_accept"):
			confirm_placement()
		elif event.is_action_pressed("rotate_prop_left"):
			placement_rotation -= 45.0
		elif event.is_action_pressed("rotate_prop_right"):
			placement_rotation += 45.0
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				placement_rotation += 15.0
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				placement_rotation -= 15.0

# ============================================
# MENU MANAGEMENT
# ============================================

func open_menu():
	visible = true
	build_mode = BuildMode.SELECTING

	if menu_panel:
		menu_panel.visible = true

	# Refresh items with current points
	_refresh_item_states()

	# Pause game or show cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	menu_opened.emit()

func close_menu():
	if build_mode == BuildMode.PLACING:
		cancel_placement()

	visible = false
	build_mode = BuildMode.NONE
	selected_prop_type = -1

	if menu_panel:
		menu_panel.visible = false
	if preview_panel:
		preview_panel.visible = false
	if status_label:
		status_label.visible = false

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	menu_closed.emit()

func toggle_menu():
	if visible:
		close_menu()
	else:
		open_menu()

# ============================================
# BUILD ITEMS
# ============================================

func _populate_build_menu():
	if not items_container:
		return

	# Clear existing
	for child in items_container.get_children():
		child.queue_free()

	# Get available props
	var props = []
	if prop_manager:
		props = prop_manager.get_available_props()
	else:
		# Fallback data
		props = _get_default_props()

	# Create item buttons
	for prop_data in props:
		var item = _create_item_button(prop_data)
		items_container.add_child(item)

func _get_default_props() -> Array:
	return [
		{"type": 0, "name": "Doorway Barricade", "cost": 200, "hp": 200.0},
		{"type": 1, "name": "Wall Section", "cost": 150, "hp": 300.0},
		{"type": 2, "name": "Window Board", "cost": 50, "hp": 75.0},
		{"type": 3, "name": "Wire Fence", "cost": 100, "hp": 100.0},
		{"type": 4, "name": "Sandbag", "cost": 75, "hp": 150.0},
		{"type": 5, "name": "Metal Sheet", "cost": 125, "hp": 200.0},
		{"type": 6, "name": "Wooden Plank", "cost": 25, "hp": 50.0},
		{"type": 7, "name": "Hallway Block", "cost": 175, "hp": 250.0},
		{"type": 8, "name": "Floor Trap", "cost": 150, "hp": 100.0},
		{"type": 9, "name": "Protective Sigil", "cost": 300, "hp": 500.0}
	]

func _create_item_button(prop_data: Dictionary) -> Control:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(120, 100)

	# Button
	var button = Button.new()
	button.custom_minimum_size = Vector2(100, 60)
	button.text = prop_data.get("name", "Item")

	var prop_type = prop_data.get("type", 0)
	button.pressed.connect(_on_item_selected.bind(prop_type, prop_data))
	button.mouse_entered.connect(_on_item_hovered.bind(prop_data))
	button.mouse_exited.connect(_on_item_unhovered)

	# Store metadata
	button.set_meta("prop_type", prop_type)
	button.set_meta("cost", prop_data.get("cost", 100))

	container.add_child(button)

	# Cost label
	var cost_label = Label.new()
	cost_label.text = "$%d" % prop_data.get("cost", 100)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(cost_label)

	# HP label
	var hp_label = Label.new()
	hp_label.text = "HP: %d" % int(prop_data.get("hp", 100.0))
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 10)
	container.add_child(hp_label)

	return container

func _refresh_item_states():
	"""Update button states based on player points"""
	if not items_container:
		return

	for container in items_container.get_children():
		var button = container.get_child(0) as Button
		if button:
			var cost = button.get_meta("cost", 0)
			button.disabled = player_points < cost

func _on_item_selected(prop_type: int, _prop_data: Dictionary):
	var cost = _prop_data.get("cost", 100)
	if player_points < cost:
		_show_status("Not enough points! Need $%d" % cost)
		return

	selected_prop_type = prop_type
	item_selected.emit(prop_type)

	# Start placement mode
	start_placement(prop_type)

func _on_item_hovered(prop_data: Dictionary):
	if not preview_panel:
		return

	preview_panel.visible = true

	if preview_name:
		preview_name.text = prop_data.get("name", "Unknown")
	if preview_cost:
		preview_cost.text = "Cost: $%d" % prop_data.get("cost", 100)
	if preview_hp:
		preview_hp.text = "HP: %d" % int(prop_data.get("hp", 100.0))
	if preview_description:
		preview_description.text = _get_prop_description(prop_data.get("type", 0))

func _on_item_unhovered():
	if preview_panel:
		preview_panel.visible = false

func _get_prop_description(prop_type: int) -> String:
	match prop_type:
		0: return "Block doorways to slow zombies"
		1: return "Strong wall section for defense"
		2: return "Board up windows quickly"
		3: return "Slows zombies passing through"
		4: return "Provides cover, blocks low zombies"
		5: return "Durable metal defense"
		6: return "Quick, cheap barrier"
		7: return "Block entire hallways"
		8: return "Damages zombies walking over"
		9: return "Magical protection, highest HP"
	return "Place to block zombies"

# ============================================
# PLACEMENT MODE
# ============================================

func start_placement(prop_type: int):
	build_mode = BuildMode.PLACING
	selected_prop_type = prop_type
	placement_rotation = 0.0

	# Hide menu, show placement UI
	if menu_panel:
		menu_panel.visible = false

	if crosshair:
		crosshair.visible = true

	if status_label:
		status_label.visible = true
		status_label.text = "LMB: Place | RMB/ESC: Cancel | Scroll: Rotate"

	# Create preview
	_create_placement_preview(prop_type)

	# Keep cursor visible during placement
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	placement_started.emit(prop_type)

func cancel_placement():
	build_mode = BuildMode.SELECTING
	selected_prop_type = -1

	# Destroy preview
	if placement_preview:
		placement_preview.queue_free()
		placement_preview = null

	# Show menu again
	if menu_panel:
		menu_panel.visible = true

	if crosshair:
		crosshair.visible = false

	if status_label:
		status_label.visible = false

	placement_cancelled.emit()

func confirm_placement():
	if not placement_valid or not placement_preview:
		_show_status("Cannot place here!")
		return

	var position = placement_preview.global_position
	var rotation = placement_preview.global_rotation

	# Get player peer ID
	var network_manager = get_node_or_null("/root/NetworkManager")
	var owner_id = 1
	if network_manager:
		owner_id = network_manager.local_player_id

	# Place prop
	if prop_manager:
		var cost = _get_prop_cost(selected_prop_type)
		if player_points >= cost:
			prop_manager.place_prop(selected_prop_type, position, rotation, owner_id)
			player_points -= cost
			_show_status("Placed!")
		else:
			_show_status("Not enough points!")
			return
	else:
		# Request placement from server
		_request_placement.rpc_id(1, selected_prop_type, position, rotation, owner_id)

	placement_confirmed.emit(selected_prop_type, position, rotation)

	# Destroy preview
	if placement_preview:
		placement_preview.queue_free()
		placement_preview = null

	# Return to menu
	cancel_placement()

func _get_prop_cost(prop_type: int) -> int:
	if prop_manager:
		return prop_manager.PROP_COSTS.get(prop_type, 100)
	return 100

func _create_placement_preview(prop_type: int):
	if placement_preview:
		placement_preview.queue_free()

	# Create a simple preview mesh
	placement_preview = Node3D.new()
	placement_preview.name = "PlacementPreview"

	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()

	# Size based on prop type
	var size = _get_prop_preview_size(prop_type)
	box_mesh.size = size
	mesh_instance.mesh = box_mesh

	# Preview material
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = COLOR_VALID
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.set_surface_override_material(0, material)

	placement_preview.add_child(mesh_instance)
	get_tree().current_scene.add_child(placement_preview)

func _get_prop_preview_size(prop_type: int) -> Vector3:
	match prop_type:
		0: return Vector3(2.0, 2.5, 0.3)  # Doorway
		1: return Vector3(3.0, 2.0, 0.2)  # Wall
		2: return Vector3(1.2, 1.0, 0.1)  # Window board
		3: return Vector3(2.0, 1.5, 0.1)  # Wire fence
		4: return Vector3(1.0, 0.5, 0.5)  # Sandbag
		5: return Vector3(1.5, 2.0, 0.05)  # Metal sheet
		6: return Vector3(0.2, 1.5, 0.05)  # Wooden plank
		7: return Vector3(2.5, 2.0, 0.5)  # Hallway block
		8: return Vector3(1.0, 0.1, 1.0)  # Floor trap
		9: return Vector3(1.5, 0.05, 1.5)  # Sigil
	return Vector3.ONE

func _update_placement_preview(delta: float):
	if not placement_preview:
		return

	# Get camera
	if not camera:
		camera = get_viewport().get_camera_3d()
	if not camera:
		return

	# Raycast from camera center
	var viewport_size = get_viewport().get_visible_rect().size
	var mouse_pos = viewport_size / 2  # Center of screen

	var from = camera.project_ray_origin(mouse_pos)
	var direction = camera.project_ray_normal(mouse_pos)
	var to = from + direction * max_placement_distance

	# Raycast
	var space_state = get_tree().current_scene.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World only
	query.exclude = [placement_preview]

	var result = space_state.intersect_ray(query)

	if result:
		var hit_pos = result.position
		var hit_normal = result.normal

		# Snap to grid
		if grid_snap > 0:
			hit_pos.x = snapped(hit_pos.x, grid_snap)
			hit_pos.z = snapped(hit_pos.z, grid_snap)

		# Offset based on normal (place against walls)
		var size = _get_prop_preview_size(selected_prop_type)
		hit_pos += hit_normal * (size.z / 2 + 0.1)

		placement_preview.global_position = hit_pos
		placement_preview.rotation.y = deg_to_rad(placement_rotation)

		# Align to surface if it's a wall
		if abs(hit_normal.y) < 0.5:  # Wall
			placement_preview.look_at(hit_pos - hit_normal, Vector3.UP)
			placement_preview.rotate_y(deg_to_rad(placement_rotation))

		# Check validity
		placement_valid = _check_placement_valid(hit_pos, size)
	else:
		# No hit - place in front of player
		var player = get_tree().get_first_node_in_group("players")
		if player:
			var forward = -player.global_transform.basis.z
			placement_preview.global_position = player.global_position + forward * 2.0
			placement_preview.rotation.y = deg_to_rad(placement_rotation)
			placement_valid = false

	# Update preview color
	var mesh_instance = placement_preview.get_child(0) as MeshInstance3D
	if mesh_instance:
		var mat = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = COLOR_VALID if placement_valid else COLOR_INVALID

func _check_placement_valid(position: Vector3, size: Vector3) -> bool:
	# Check for overlaps
	var space_state = get_tree().current_scene.get_world_3d().direct_space_state

	var shape = BoxShape3D.new()
	shape.size = size * 0.9  # Slightly smaller to allow close placement

	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = 8  # Props layer

	var results = space_state.intersect_shape(query)
	if results.size() > 0:
		return false

	# Check not too close to spawn points
	var spawn_points = get_tree().get_nodes_in_group("player_spawn")
	for spawn in spawn_points:
		if position.distance_to(spawn.global_position) < 2.0:
			return false

	return true

# ============================================
# UTILITIES
# ============================================

func set_player_points(points: int):
	player_points = points
	_refresh_item_states()

func _show_status(text: String):
	if status_label:
		status_label.text = text
		status_label.visible = true

		# Hide after delay
		await get_tree().create_timer(2.0).timeout
		if build_mode != BuildMode.PLACING:
			status_label.visible = false

@rpc("any_peer", "reliable")
func _request_placement(prop_type: int, position: Vector3, rotation: Vector3, owner_id: int):
	if not multiplayer.is_server():
		return

	if prop_manager:
		prop_manager.place_prop(prop_type, position, rotation, owner_id)
