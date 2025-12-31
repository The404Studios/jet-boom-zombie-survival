extends Area3D
class_name LootItem

# Enhanced Loot Item with magnetic pickup, hover effects, and easy interaction
# Supports world-space tooltips and quick pickup with E key

signal picked_up(player: Node)
signal hover_started
signal hover_ended

@export var item_data: Resource = null
@export var auto_pickup: bool = true  # Default to auto pickup for ammo/health
@export var pickup_radius: float = 2.5  # Increased for easier pickup
@export var magnetic_radius: float = 4.0  # Items attract to player in this range
@export var magnetic_speed: float = 8.0  # How fast items move toward player
@export var despawn_time: float = 300.0  # 5 minutes
@export var bob_amplitude: float = 0.15
@export var bob_speed: float = 2.5
@export var rotation_speed: float = 1.5
@export var show_world_tooltip: bool = true
@export var tooltip_distance: float = 10.0
@export var pickup_key_prompt: bool = true  # Show "Press E to pickup"

var item_mesh: MeshInstance3D = null
var glow_light: OmniLight3D = null
var label: Label3D = null
var pickup_prompt: Label3D = null
var world_tooltip: Control = null
var particle_trail: GPUParticles3D = null

var despawn_timer: float = 0.0
var initial_y: float = 0.0
var bob_time: float = 0.0
var is_hovered: bool = false
var hover_player: Node = null
var is_being_attracted: bool = false
var target_player: Node = null

# Loot type tracking (from loot spawner)
var loot_type: String = ""
var loot_subtype: String = ""
var loot_quantity: int = 1

func _ready():
	add_to_group("loot")
	add_to_group("interactable")

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Store initial position
	initial_y = position.y

	# Create visual if no mesh
	if not item_mesh:
		_create_default_visual()

	# Create label
	_create_label()

	# Create pickup prompt
	_create_pickup_prompt()

	# Set despawn timer
	despawn_timer = despawn_time

	# Random rotation start
	bob_time = randf() * TAU

	# Auto pickup for common loot types
	if loot_type in ["ammo", "health", "material"]:
		auto_pickup = true
	elif item_data and "item_type" in item_data:
		# Auto pickup for ammo, consumables, materials
		if item_data.item_type in [1, 8, 9]:  # AMMO, CONSUMABLE, MATERIAL
			auto_pickup = true

	# Track spawn time for garbage collection
	set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)

	# Register with garbage collector
	var gc = get_node_or_null("/root/GarbageCollector")
	if gc and gc.has_method("track_loot"):
		gc.track_loot(self)

	# Spawn animation
	_play_spawn_animation()

func _process(delta):
	# Handle magnetic attraction
	if is_being_attracted and target_player and is_instance_valid(target_player):
		var direction = (target_player.global_position + Vector3.UP * 0.5 - global_position).normalized()
		var distance = global_position.distance_to(target_player.global_position)

		# Accelerate as we get closer
		var speed_mult = max(1.0, (magnetic_radius - distance) / magnetic_radius * 2.0)
		global_position += direction * magnetic_speed * speed_mult * delta

		# Check if close enough to pickup
		if distance < 1.0:
			pickup(target_player)
			return
	else:
		# Bob up and down
		bob_time += delta * bob_speed
		position.y = initial_y + sin(bob_time) * bob_amplitude

		# Rotate
		rotate_y(delta * rotation_speed)

	# Despawn timer
	despawn_timer -= delta
	if despawn_timer <= 0:
		_play_despawn_animation()
		return

	# Flash when about to despawn
	if despawn_timer < 10.0:
		var flash = sin(Time.get_ticks_msec() * 0.01) > 0
		if item_mesh:
			item_mesh.visible = flash or despawn_timer < 5.0

	# Update hover state for world tooltip
	if show_world_tooltip:
		_update_hover_state()

	# Check for magnetic attraction
	_check_magnetic_attraction()

	# Handle pickup key input when hovered
	if is_hovered and hover_player and Input.is_action_just_pressed("interact"):
		pickup(hover_player)

func _check_magnetic_attraction():
	"""Check if any player is close enough for magnetic pickup"""
	if is_being_attracted or not auto_pickup:
		return

	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if not is_instance_valid(player):
			continue

		var distance = global_position.distance_to(player.global_position)
		if distance < magnetic_radius:
			is_being_attracted = true
			target_player = player
			_start_attraction_effect()
			break

func _start_attraction_effect():
	"""Visual effect when item starts being attracted"""
	if glow_light:
		var tween = create_tween()
		tween.tween_property(glow_light, "light_energy", 1.5, 0.2)

func _play_spawn_animation():
	"""Animate item appearing"""
	scale = Vector3.ZERO
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE, 0.4)

func _play_despawn_animation():
	"""Animate item disappearing"""
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(queue_free)

func _create_pickup_prompt():
	"""Create the 'Press E' pickup prompt"""
	if not pickup_key_prompt:
		return

	pickup_prompt = Label3D.new()
	pickup_prompt.text = "[E] Pickup"
	pickup_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pickup_prompt.font_size = 14
	pickup_prompt.position = Vector3(0, 0.3, 0)
	pickup_prompt.modulate = Color(1, 1, 1, 0.9)
	pickup_prompt.outline_modulate = Color(0, 0, 0)
	pickup_prompt.outline_size = 4
	pickup_prompt.visible = false
	add_child(pickup_prompt)

func _update_hover_state():
	"""Check if player is looking at this item and update tooltip"""
	var players = get_tree().get_nodes_in_group("player")
	var was_hovered = is_hovered
	is_hovered = false
	hover_player = null

	for player in players:
		if not is_instance_valid(player):
			continue

		# Check distance
		var distance = global_position.distance_to(player.global_position)
		if distance > tooltip_distance:
			continue

		# Check if player is looking at this item
		var camera = player.get_node_or_null("Camera3D")
		if not camera:
			continue

		var interact_ray = player.get_node_or_null("Camera3D/InteractRay")
		if interact_ray and interact_ray.is_colliding():
			if interact_ray.get_collider() == self:
				is_hovered = true
				hover_player = player
				break

	# Handle hover state changes
	if is_hovered and not was_hovered:
		_on_hover_start()
	elif not is_hovered and was_hovered:
		_on_hover_end()

func _on_hover_start():
	"""Called when player starts looking at this item"""
	hover_started.emit()

	# Highlight the item with glow animation
	if item_mesh and item_mesh.material_override:
		var mat = item_mesh.material_override as StandardMaterial3D
		if mat:
			var tween = create_tween()
			tween.tween_property(mat, "emission_energy_multiplier", 2.0, 0.15)

	# Increase glow light
	if glow_light:
		var tween = create_tween()
		tween.tween_property(glow_light, "light_energy", 0.8, 0.15)

	# Show pickup prompt
	if pickup_prompt:
		pickup_prompt.visible = true
		pickup_prompt.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(pickup_prompt, "modulate:a", 1.0, 0.15)

	# Scale up slightly
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(1.15, 1.15, 1.15), 0.15)

	# Show world tooltip
	_show_world_tooltip()

func _on_hover_end():
	"""Called when player stops looking at this item"""
	hover_ended.emit()

	# Remove highlight
	if item_mesh and item_mesh.material_override:
		var mat = item_mesh.material_override as StandardMaterial3D
		if mat:
			var tween = create_tween()
			tween.tween_property(mat, "emission_energy_multiplier", 0.5, 0.15)

	# Reduce glow light
	if glow_light:
		var tween = create_tween()
		tween.tween_property(glow_light, "light_energy", 0.3, 0.15)

	# Hide pickup prompt
	if pickup_prompt:
		var tween = create_tween()
		tween.tween_property(pickup_prompt, "modulate:a", 0.0, 0.1)
		tween.tween_callback(func(): pickup_prompt.visible = false)

	# Scale back
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.15)

	# Hide world tooltip
	_hide_world_tooltip()

func _show_world_tooltip():
	"""Show world-space tooltip for this item"""
	# Try to use the global WorldTooltip system
	var tooltip_system = get_tree().get_first_node_in_group("world_tooltip")
	if tooltip_system and tooltip_system.has_method("show_for_item"):
		tooltip_system.show_for_item(self, item_data)

func _hide_world_tooltip():
	"""Hide world-space tooltip"""
	var tooltip_system = get_tree().get_first_node_in_group("world_tooltip")
	if tooltip_system and tooltip_system.has_method("hide_tooltip"):
		tooltip_system.hide_tooltip()

func _on_body_exited(body: Node3D):
	"""Handle player leaving proximity"""
	if body.is_in_group("player"):
		if hover_player == body:
			_on_hover_end()

func _create_default_visual():
	# Create a simple visual representation
	item_mesh = MeshInstance3D.new()
	add_child(item_mesh)

	var mesh: Mesh

	# Choose mesh based on loot type
	match loot_type:
		"ammo":
			var box = BoxMesh.new()
			box.size = Vector3(0.2, 0.15, 0.3)
			mesh = box
		"health":
			var box = BoxMesh.new()
			box.size = Vector3(0.25, 0.15, 0.25)
			mesh = box
		"weapon":
			var box = BoxMesh.new()
			box.size = Vector3(0.4, 0.2, 0.15)
			mesh = box
		"material":
			var sphere = SphereMesh.new()
			sphere.radius = 0.15
			sphere.height = 0.3
			mesh = sphere
		"gear":
			var box = BoxMesh.new()
			box.size = Vector3(0.3, 0.3, 0.2)
			mesh = box
		"augment":
			var prism = PrismMesh.new()
			prism.size = Vector3(0.25, 0.3, 0.25)
			mesh = prism
		_:
			var box = BoxMesh.new()
			box.size = Vector3(0.25, 0.25, 0.25)
			mesh = box

	item_mesh.mesh = mesh

	# Apply material with color based on type
	var mat = StandardMaterial3D.new()
	mat.albedo_color = _get_type_color()
	mat.emission_enabled = true
	mat.emission = _get_type_color()
	mat.emission_energy_multiplier = 0.5
	item_mesh.material_override = mat

	# Add glow light
	glow_light = OmniLight3D.new()
	glow_light.light_color = _get_type_color()
	glow_light.light_energy = 0.3
	glow_light.omni_range = 2.0
	add_child(glow_light)

func _get_type_color() -> Color:
	match loot_type:
		"ammo": return Color(0.9, 0.7, 0.2)  # Yellow
		"health": return Color(0.2, 0.9, 0.3)  # Green
		"weapon": return Color(0.9, 0.3, 0.2)  # Red
		"material": return Color(0.5, 0.5, 0.9)  # Blue
		"gear": return Color(0.8, 0.4, 0.9)  # Purple
		"augment": return Color(0.9, 0.2, 0.9)  # Magenta
	return Color(0.7, 0.7, 0.7)  # Gray default

func _create_label():
	label = Label3D.new()
	label.text = _get_display_name()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 16
	label.position = Vector3(0, 0.5, 0)
	label.modulate = _get_type_color()
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 3
	add_child(label)

func _get_display_name() -> String:
	if item_data and "item_name" in item_data:
		return item_data.item_name

	# Generate name from loot data
	var loot_name = loot_subtype.capitalize().replace("_", " ") if loot_subtype else loot_type.capitalize()

	if loot_quantity > 1:
		loot_name += " x%d" % loot_quantity

	return loot_name

func set_item_data(data: Resource):
	item_data = data

	# Update visual
	if item_data and "mesh_scene" in item_data and item_data.mesh_scene:
		if item_mesh:
			item_mesh.queue_free()
		item_mesh = item_data.mesh_scene.instantiate()
		add_child(item_mesh)

	# Update label
	if label:
		label.text = _get_display_name()

	# Update color based on rarity
	if item_data and "rarity" in item_data:
		var rarity_color = _get_rarity_color(item_data.rarity)
		if label:
			label.modulate = rarity_color
		if glow_light:
			glow_light.light_color = rarity_color

func set_loot_data(type: String, subtype: String, quantity: int = 1):
	loot_type = type
	loot_subtype = subtype
	loot_quantity = quantity

	# Recreate visuals
	if item_mesh:
		item_mesh.queue_free()
		item_mesh = null
	_create_default_visual()

	if label:
		label.text = _get_display_name()

func _get_rarity_color(rarity) -> Color:
	match rarity:
		0: return Color(0.7, 0.7, 0.7)  # Common - Gray
		1: return Color(0.2, 0.8, 0.2)  # Uncommon - Green
		2: return Color(0.2, 0.5, 1.0)  # Rare - Blue
		3: return Color(0.7, 0.3, 1.0)  # Epic - Purple
		4: return Color(1.0, 0.5, 0.0)  # Legendary - Orange
		5: return Color(1.0, 0.2, 0.2)  # Mythic - Red
	return Color.WHITE

func get_item_data() -> Resource:
	return item_data

func _on_body_entered(body: Node3D):
	if not body.is_in_group("player"):
		return

	if auto_pickup:
		pickup(body)

func interact(player: Node):
	pickup(player)

func pickup(player: Node):
	# Try to give item to player
	var success = false

	if item_data:
		# Try to add to inventory
		if "inventory" in player and player.inventory:
			if player.inventory.has_method("add_item"):
				success = player.inventory.add_item(item_data, 1)
		# Try direct pickup method
		elif player.has_method("pickup_item"):
			success = player.pickup_item(self)
	else:
		# Handle loot type pickups
		success = _handle_loot_pickup(player)

	if success:
		picked_up.emit(player)

		# Play pickup sound
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx("pickup")

		# Notify player
		if player.has_method("show_pickup_message"):
			player.show_pickup_message(_get_display_name())

		queue_free()

func _handle_loot_pickup(player: Node) -> bool:
	match loot_type:
		"ammo":
			return _give_ammo(player)
		"health":
			return _give_health(player)
		"weapon":
			return _give_weapon(player)
		"material":
			return _give_material(player)
		"gear":
			return _give_gear(player)
		"augment":
			return _give_augment(player)
	return false

func _give_ammo(player: Node) -> bool:
	if "reserve_ammo" in player:
		player.reserve_ammo += loot_quantity
		return true
	return false

func _give_health(player: Node) -> bool:
	var heal_amount = get_meta("heal_amount", 25)
	if player.has_method("heal"):
		player.heal(heal_amount)
		return true
	elif "current_health" in player and "max_health" in player:
		player.current_health = min(player.current_health + heal_amount, player.max_health)
		return true
	return false

func _give_weapon(player: Node) -> bool:
	# For now, add to inventory if available
	if "inventory" in player and player.inventory:
		# Would need to create weapon data
		return true
	return false

func _give_material(_player: Node) -> bool:
	# Add to player persistence
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		var material_key = loot_subtype
		if not persistence.player_data.has("materials"):
			persistence.player_data["materials"] = {}
		if persistence.player_data.materials.has(material_key):
			persistence.player_data.materials[material_key] += loot_quantity
		else:
			persistence.player_data.materials[material_key] = loot_quantity
		return true
	return false

func _give_gear(player: Node) -> bool:
	# Add gear to inventory
	if "inventory" in player and player.inventory:
		if player.inventory.has_method("add_item") and item_data:
			return player.inventory.add_item(item_data, 1)
	return false

func _give_augment(player: Node) -> bool:
	# Add augment to inventory
	if "inventory" in player and player.inventory:
		if player.inventory.has_method("add_item") and item_data:
			return player.inventory.add_item(item_data, 1)
	return false

func flash_highlight():
	"""Flash the item to draw attention"""
	if item_mesh:
		var tween = create_tween()
		tween.tween_property(item_mesh, "modulate:a", 0.5, 0.2)
		tween.tween_property(item_mesh, "modulate:a", 1.0, 0.2)
		tween.set_loops(3)
