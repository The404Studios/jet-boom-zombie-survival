extends Area3D
class_name LootItem

# Loot Item - Interactable pickup item that can contain weapons, ammo, materials, gear, etc.

signal picked_up(player: Node)

@export var item_data: Resource = null
@export var auto_pickup: bool = false
@export var pickup_radius: float = 1.5
@export var despawn_time: float = 300.0  # 5 minutes
@export var bob_amplitude: float = 0.1
@export var bob_speed: float = 2.0
@export var rotation_speed: float = 1.0

var item_mesh: MeshInstance3D = null
var glow_light: OmniLight3D = null
var label: Label3D = null

var despawn_timer: float = 0.0
var initial_y: float = 0.0
var bob_time: float = 0.0

# Loot type tracking (from loot spawner)
var loot_type: String = ""
var loot_subtype: String = ""
var loot_quantity: int = 1

func _ready():
	add_to_group("loot")
	add_to_group("interactable")

	# Connect signals
	body_entered.connect(_on_body_entered)

	# Store initial position
	initial_y = position.y

	# Create visual if no mesh
	if not item_mesh:
		_create_default_visual()

	# Create label
	_create_label()

	# Set despawn timer
	despawn_timer = despawn_time

	# Random rotation start
	bob_time = randf() * TAU

func _process(delta):
	# Bob up and down
	bob_time += delta * bob_speed
	position.y = initial_y + sin(bob_time) * bob_amplitude

	# Rotate
	rotate_y(delta * rotation_speed)

	# Despawn timer
	despawn_timer -= delta
	if despawn_timer <= 0:
		queue_free()

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
	var name = loot_subtype.capitalize().replace("_", " ") if loot_subtype else loot_type.capitalize()

	if loot_quantity > 1:
		name += " x%d" % loot_quantity

	return name

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

func _give_material(player: Node) -> bool:
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
