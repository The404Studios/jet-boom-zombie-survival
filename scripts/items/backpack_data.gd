extends Resource
class_name BackpackData

# Backpack item that expands inventory grid size

@export var backpack_name: String = "Basic Backpack"
@export var description: String = "A simple backpack that expands your inventory."
@export var icon: Texture2D

# Expansion properties
@export var extra_rows: int = 2  # Additional rows added to inventory
@export var extra_weight_capacity: float = 10.0  # Additional weight capacity
@export var storage_slots: int = 0  # Some backpacks may have internal storage

# Item properties
@export var rarity: int = 0  # 0=Common, 1=Uncommon, 2=Rare, 3=Epic, 4=Legendary, 5=Mythic
@export var price: int = 500
@export var weight: float = 2.0

# Grid size (for inventory placement)
@export var grid_size: Vector2i = Vector2i(3, 3)

# Item type identifier
var item_type: int = ItemDataExtended.ItemType.MATERIAL  # Treat as material until equipped

func get_rarity_color() -> Color:
	match rarity:
		0: return Color(0.6, 0.6, 0.6)      # Common - Gray
		1: return Color(0.2, 0.8, 0.2)      # Uncommon - Green
		2: return Color(0.2, 0.4, 1.0)      # Rare - Blue
		3: return Color(0.6, 0.2, 0.8)      # Epic - Purple
		4: return Color(1.0, 0.6, 0.0)      # Legendary - Orange
		5: return Color(1.0, 0.2, 0.2)      # Mythic - Red
		_: return Color(0.6, 0.6, 0.6)

func get_rarity_name() -> String:
	match rarity:
		0: return "Common"
		1: return "Uncommon"
		2: return "Rare"
		3: return "Epic"
		4: return "Legendary"
		5: return "Mythic"
		_: return "Unknown"

func get_expansion_description() -> String:
	var desc = ""
	if extra_rows > 0:
		desc += "+%d inventory rows\n" % extra_rows
	if extra_weight_capacity > 0:
		desc += "+%.0f weight capacity\n" % extra_weight_capacity
	if storage_slots > 0:
		desc += "%d internal slots\n" % storage_slots
	return desc

static func create_basic_backpack() -> BackpackData:
	var bp = BackpackData.new()
	bp.backpack_name = "Basic Backpack"
	bp.description = "A simple canvas backpack. Provides modest storage expansion."
	bp.extra_rows = 1
	bp.extra_weight_capacity = 5.0
	bp.rarity = 0
	bp.price = 300
	bp.weight = 1.5
	bp.grid_size = Vector2i(2, 2)
	return bp

static func create_military_backpack() -> BackpackData:
	var bp = BackpackData.new()
	bp.backpack_name = "Military Backpack"
	bp.description = "A sturdy military-grade pack with reinforced straps."
	bp.extra_rows = 2
	bp.extra_weight_capacity = 15.0
	bp.rarity = 1
	bp.price = 800
	bp.weight = 2.5
	bp.grid_size = Vector2i(3, 3)
	return bp

static func create_tactical_backpack() -> BackpackData:
	var bp = BackpackData.new()
	bp.backpack_name = "Tactical Backpack"
	bp.description = "High-capacity tactical pack with MOLLE webbing."
	bp.extra_rows = 3
	bp.extra_weight_capacity = 20.0
	bp.rarity = 2
	bp.price = 1500
	bp.weight = 3.0
	bp.grid_size = Vector2i(3, 3)
	return bp

static func create_survivor_backpack() -> BackpackData:
	var bp = BackpackData.new()
	bp.backpack_name = "Survivor's Pack"
	bp.description = "A well-worn pack that has seen many apocalypses."
	bp.extra_rows = 4
	bp.extra_weight_capacity = 25.0
	bp.storage_slots = 4
	bp.rarity = 3
	bp.price = 3000
	bp.weight = 3.5
	bp.grid_size = Vector2i(3, 3)
	return bp

static func create_legendary_pack() -> BackpackData:
	var bp = BackpackData.new()
	bp.backpack_name = "Void Carrier"
	bp.description = "Rumored to contain a pocket dimension. Items seem lighter inside."
	bp.extra_rows = 5
	bp.extra_weight_capacity = 40.0
	bp.storage_slots = 8
	bp.rarity = 4
	bp.price = 8000
	bp.weight = 1.0  # Magically light
	bp.grid_size = Vector2i(4, 4)
	return bp

static func get_all_backpacks() -> Array[BackpackData]:
	return [
		create_basic_backpack(),
		create_military_backpack(),
		create_tactical_backpack(),
		create_survivor_backpack(),
		create_legendary_pack()
	]
