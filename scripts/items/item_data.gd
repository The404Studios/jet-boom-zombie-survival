extends Resource
class_name ItemData

enum ItemType {
	WEAPON,
	AMMO,
	HEALTH,
	ARMOR,
	CONSUMABLE,
	MATERIAL
}

@export var item_name: String = ""
@export var item_type: ItemType = ItemType.CONSUMABLE
@export var description: String = ""
@export var icon: Texture2D
@export var mesh_scene: PackedScene
@export var stack_size: int = 1
@export var weight: float = 1.0
@export var value: int = 100

# Weapon specific
@export var damage: float = 10.0
@export var fire_rate: float = 0.1
@export var magazine_size: int = 30
@export var reload_time: float = 2.0
@export var weapon_range: float = 100.0

# Consumable specific
@export var health_restore: float = 0.0
@export var armor_restore: float = 0.0
@export var stamina_restore: float = 0.0

# Armor specific
@export var armor_value: float = 0.0
@export var armor_durability: float = 100.0
