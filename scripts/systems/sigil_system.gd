extends Area3D
class_name Sigil

@export var max_health: float = 1000.0
@export var protection_radius: float = 15.0
@export var shop_items: Array[ItemData] = []

var current_health: float = 1000.0
var players_in_range: Array = []  # Changed from Array[Player] for compatibility

# Shop and upgrade systems
var sigil_shop: SigilShop = null
var remantler: RemantlerSystem = null
var shop_panel: Control = null
var remantler_panel: Control = null

# Interaction state
var current_interacting_player: Node = null
var interaction_mode: String = ""  # "shop", "remantler", "extract"

@onready var mesh: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var collision: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null
@onready var shop_ui: Control = $ShopUI if has_node("ShopUI") else null

signal sigil_destroyed
signal sigil_damaged(current_hp: float, max_hp: float)
signal player_entered_zone(player: Node)
signal player_exited_zone(player: Node)
signal shop_opened(player: Node)
signal shop_closed
signal remantler_opened(player: Node)
signal remantler_closed

func _ready():
	add_to_group("sigil")
	add_to_group("extract_zone")
	add_to_group("interactable")
	current_health = max_health

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Set up collision shape for protection zone
	if collision and not collision.shape:
		var sphere = SphereShape3D.new()
		sphere.radius = protection_radius
		collision.shape = sphere

	# Visual effect
	create_sigil_visual()

	# Initialize shop systems
	await get_tree().create_timer(0.1).timeout
	_initialize_systems()

func _initialize_systems():
	# Create SigilShop
	sigil_shop = SigilShop.new()
	sigil_shop.name = "SigilShop"
	add_child(sigil_shop)

	# Create RemantlerSystem
	remantler = RemantlerSystem.new()
	remantler.name = "RemantlerSystem"
	remantler.sigil_shop = sigil_shop
	add_child(remantler)

	# Create Shop UI
	shop_panel = SigilShopPanel.create_shop_scene()
	shop_panel.visible = false
	add_child(shop_panel)
	if shop_panel.has_method("_find_sigil_shop"):
		shop_panel._find_sigil_shop()

	# Create Remantler UI
	remantler_panel = RemantlerPanel.create_panel_scene()
	remantler_panel.visible = false
	add_child(remantler_panel)

	# Connect shop signals
	if shop_panel.has_signal("shop_closed"):
		shop_panel.shop_closed.connect(_on_shop_closed)
	if remantler_panel.has_signal("panel_closed"):
		remantler_panel.panel_closed.connect(_on_remantler_closed)

func _on_body_entered(body):
	if body.is_in_group("player"):
		players_in_range.append(body)
		player_entered_zone.emit(body)
		_show_interaction_prompt(body)

func _on_body_exited(body):
	if body.is_in_group("player"):
		players_in_range.erase(body)
		player_exited_zone.emit(body)
		_hide_interaction_prompt(body)

func _show_interaction_prompt(player: Node):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_interact_prompt"):
		hud.show_interact_prompt("[E] Shop  |  [R] Remantler  |  [X] Extract")

func _hide_interaction_prompt(player: Node):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("hide_interact_prompt"):
		hud.hide_interact_prompt()

func _input(event):
	if players_in_range.size() == 0:
		return

	var player = players_in_range[0]

	# Shop hotkey
	if event.is_action_pressed("interact"):  # E key
		open_shop(player)
		get_viewport().set_input_as_handled()
	# Remantler hotkey
	elif event.is_action_pressed("reload"):  # R key
		open_remantler(player)
		get_viewport().set_input_as_handled()
	# Extract hotkey
	elif event.is_action_pressed("extract"):  # X key
		extract(player)
		get_viewport().set_input_as_handled()

func create_sigil_visual():
	# Create glowing crystal/sigil visual
	if not mesh:
		mesh = MeshInstance3D.new()
		add_child(mesh)
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(1, 2, 1)
		mesh.mesh = box_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.6, 1.0)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	current_health -= amount
	current_health = max(current_health, 0)

	sigil_damaged.emit(current_health, max_health)

	# Visual feedback
	flash_damage()

	if current_health <= 0:
		destroy()

func flash_damage():
	if mesh:
		var tween = create_tween()
		var mat = mesh.material_override as StandardMaterial3D
		var original_color = mat.albedo_color
		tween.tween_property(mat, "albedo_color", Color.RED, 0.1)
		tween.tween_property(mat, "albedo_color", original_color, 0.1)

func destroy():
	sigil_destroyed.emit()
	# Game over logic here
	queue_free()

func interact(player: Node):
	# Open shop by default
	open_shop(player)

func open_shop(player: Node):
	"""Open the sigil shop interface"""
	current_interacting_player = player
	interaction_mode = "shop"

	if shop_panel and shop_panel.has_method("open_shop"):
		shop_panel.open_shop(player)
		shop_opened.emit(player)
	elif shop_ui:
		shop_ui.visible = true
		if shop_ui.has_method("setup_shop"):
			shop_ui.setup_shop(shop_items, player)

func open_remantler(player: Node):
	"""Open the remantler upgrade interface"""
	current_interacting_player = player
	interaction_mode = "remantler"

	if remantler_panel and remantler_panel.has_method("open_panel"):
		remantler_panel.open_panel(player)
		remantler_opened.emit(player)

func _on_shop_closed():
	current_interacting_player = null
	interaction_mode = ""
	shop_closed.emit()

func _on_remantler_closed():
	current_interacting_player = null
	interaction_mode = ""
	remantler_closed.emit()

func extract(player: Node):
	"""Handle player extraction"""
	# Transfer player inventory to stash
	if "inventory" in player and player.inventory:
		for item_data in player.inventory.inventory:
			player.inventory.transfer_to_stash(item_data.item, item_data.quantity)

	# Save player data
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		persistence.save_player_data()

	# Award extraction bonus
	if sigil_shop:
		sigil_shop.add_sigils(100, "Extraction bonus")

	# Notify
	if has_node("/root/ChatSystem"):
		get_node("/root/ChatSystem").emit_system_message("Extraction successful! +100 Sigils")

	print("Extraction successful!")

func buy_item(player: Node, item: ItemData) -> bool:
	# Use sigil shop for purchases
	if sigil_shop and item:
		# Find matching shop item
		for key in sigil_shop.shop_items:
			var shop_item = sigil_shop.shop_items[key]
			if shop_item.item_data == item:
				return sigil_shop.purchase_item(key, player)
	return false

func is_player_in_zone(player: Node) -> bool:
	return player in players_in_range

func get_sigil_shop() -> SigilShop:
	return sigil_shop

func get_remantler() -> RemantlerSystem:
	return remantler

func add_sigils_to_player(amount: int, reason: String = ""):
	"""Add sigils to the player's currency"""
	if sigil_shop:
		sigil_shop.add_sigils(amount, reason)
