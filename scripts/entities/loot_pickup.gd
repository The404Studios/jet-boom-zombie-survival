extends Node3D
class_name LootPickup

## World loot pickup entity
## Spawned when zombies die, can be picked up by players

signal picked_up(by_peer_id: int)

@export var despawn_time: float = 120.0
@export var bob_height: float = 0.1
@export var bob_speed: float = 2.0
@export var rotation_speed: float = 1.0

var items: Array = []
var pickup_id: int = 0
var spawn_time: float = 0.0
var initial_y: float = 0.0

# Visual
var mesh_instance: MeshInstance3D = null
var rarity_light: OmniLight3D = null

# Rarity colors for glow
const RARITY_GLOW_COLORS = {
	0: Color(0.7, 0.7, 0.7),      # Common - white/gray
	1: Color(0.2, 0.9, 0.2),      # Uncommon - green
	2: Color(0.2, 0.4, 1.0),      # Rare - blue
	3: Color(0.8, 0.2, 1.0),      # Epic - purple
	4: Color(1.0, 0.7, 0.0)       # Legendary - orange/gold
}

func _ready():
	initial_y = position.y
	spawn_time = Time.get_ticks_msec() / 1000.0
	
	_create_visual()
	
	# Auto despawn timer
	if despawn_time > 0:
		var timer = get_tree().create_timer(despawn_time)
		timer.timeout.connect(_on_despawn_timeout)

func _create_visual():
	# Create mesh
	mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	mesh_instance.mesh = box
	add_child(mesh_instance)
	
	# Create glow based on highest rarity item
	var highest_rarity = 0
	for item in items:
		if item.has("rarity") and item.rarity > highest_rarity:
			highest_rarity = item.rarity
	
	rarity_light = OmniLight3D.new()
	rarity_light.light_color = RARITY_GLOW_COLORS.get(highest_rarity, Color.WHITE)
	rarity_light.light_energy = 0.5 + (highest_rarity * 0.3)
	rarity_light.omni_range = 2.0
	add_child(rarity_light)
	
	# Set mesh material color
	var material = StandardMaterial3D.new()
	material.albedo_color = RARITY_GLOW_COLORS.get(highest_rarity, Color.WHITE)
	material.emission_enabled = true
	material.emission = RARITY_GLOW_COLORS.get(highest_rarity, Color.WHITE) * 0.5
	mesh_instance.material_override = material

func _process(delta):
	# Bob up and down
	var time = Time.get_ticks_msec() / 1000.0
	position.y = initial_y + sin(time * bob_speed) * bob_height
	
	# Rotate
	rotation.y += rotation_speed * delta

func initialize(loot_items: Array, id: int = 0):
	items = loot_items
	pickup_id = id if id > 0 else randi()
	
	if mesh_instance:
		_update_visual_for_rarity()

func _update_visual_for_rarity():
	var highest_rarity = 0
	for item in items:
		if item.has("rarity") and item.rarity > highest_rarity:
			highest_rarity = item.rarity
	
	if rarity_light:
		rarity_light.light_color = RARITY_GLOW_COLORS.get(highest_rarity, Color.WHITE)
		rarity_light.light_energy = 0.5 + (highest_rarity * 0.3)
	
	if mesh_instance:
		var material = mesh_instance.material_override as StandardMaterial3D
		if material:
			material.albedo_color = RARITY_GLOW_COLORS.get(highest_rarity, Color.WHITE)
			material.emission = RARITY_GLOW_COLORS.get(highest_rarity, Color.WHITE) * 0.5

func try_pickup(peer_id: int, inventory_system: Node) -> bool:
	if items.is_empty():
		return false
	
	var picked_items = []
	var remaining_items = []
	
	for item_data in items:
		var success = false
		if inventory_system and inventory_system.has_method("add_item_by_id"):
			var item = inventory_system.add_item_by_id(
				item_data.get("item_id", ""),
				"backpack",
				item_data.get("quantity", 1)
			)
			success = item != null
		
		if success:
			picked_items.append(item_data)
		else:
			remaining_items.append(item_data)
	
	items = remaining_items
	
	if picked_items.size() > 0:
		picked_up.emit(peer_id)
		
		if items.is_empty():
			queue_free()
			return true
		else:
			_update_visual_for_rarity()
	
	return picked_items.size() > 0

func get_items_preview() -> Array:
	var preview = []
	for item in items:
		preview.append({
			"id": item.get("item_id", "unknown"),
			"rarity": item.get("rarity", 0),
			"quantity": item.get("quantity", 1)
		})
	return preview

func _on_despawn_timeout():
	if is_instance_valid(self):
		queue_free()

# ============================================
# NETWORK SYNC
# ============================================

func serialize() -> Dictionary:
	return {
		"pickup_id": pickup_id,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"items": items,
		"spawn_time": spawn_time
	}

static func deserialize(data: Dictionary) -> LootPickup:
	var pickup = LootPickup.new()
	pickup.pickup_id = data.get("pickup_id", 0)
	pickup.position = Vector3(
		data.get("position", {}).get("x", 0),
		data.get("position", {}).get("y", 0),
		data.get("position", {}).get("z", 0)
	)
	pickup.items = data.get("items", [])
	pickup.spawn_time = data.get("spawn_time", 0)
	return pickup

@rpc("authority", "call_remote", "reliable")
func sync_pickup_state(data: Dictionary):
	position = Vector3(
		data.get("position", {}).get("x", position.x),
		data.get("position", {}).get("y", position.y),
		data.get("position", {}).get("z", position.z)
	)
	items = data.get("items", items)
	_update_visual_for_rarity()

@rpc("any_peer", "call_local", "reliable")
func request_pickup():
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	
	# Server processes pickup
	if multiplayer.is_server():
		var inventory_system = get_node_or_null("/root/InventorySystem")
		if try_pickup(peer_id, inventory_system):
			confirm_pickup.rpc(peer_id, items)

@rpc("authority", "call_remote", "reliable")
func confirm_pickup(peer_id: int, picked_items: Array):
	if peer_id == multiplayer.get_unique_id():
		# Add items to local inventory
		var inventory_system = get_node_or_null("/root/InventorySystem")
		if inventory_system:
			for item_data in picked_items:
				inventory_system.add_item_by_id(
					item_data.get("item_id", ""),
					"backpack",
					item_data.get("quantity", 1)
				)
