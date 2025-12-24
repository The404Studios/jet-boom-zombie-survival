extends Area3D
class_name Sigil

@export var max_health: float = 1000.0
@export var protection_radius: float = 15.0
@export var shop_items: Array[ItemData] = []

var current_health: float = 1000.0
var players_in_range: Array[Player] = []

@onready var mesh: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var collision: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null
@onready var shop_ui: Control = $ShopUI if has_node("ShopUI") else null

signal sigil_destroyed
signal sigil_damaged(current_hp: float, max_hp: float)
signal player_entered_zone(player: Player)
signal player_exited_zone(player: Player)

func _ready():
	add_to_group("sigil")
	add_to_group("extract_zone")
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

func _on_body_entered(body):
	if body is Player:
		players_in_range.append(body)
		player_entered_zone.emit(body)

func _on_body_exited(body):
	if body is Player:
		players_in_range.erase(body)
		player_exited_zone.emit(body)

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

func interact(player: Player):
	# Open shop
	open_shop(player)

func open_shop(player: Player):
	# This would open a shop UI for the player
	if shop_ui:
		shop_ui.visible = true
		if shop_ui.has_method("setup_shop"):
			shop_ui.setup_shop(shop_items, player)

func extract(player: Player):
	# Transfer player inventory to stash
	for item_data in player.inventory.inventory:
		player.inventory.transfer_to_stash(item_data.item, item_data.quantity)

	# Could trigger end of round or return to safe zone
	print("Extraction successful!")

func buy_item(player: Player, item: ItemData) -> bool:
	# Check if player has enough currency (value)
	# For simplicity, using a simple check
	if player.inventory.add_item(item, 1):
		return true
	return false

func is_player_in_zone(player: Player) -> bool:
	return player in players_in_range
