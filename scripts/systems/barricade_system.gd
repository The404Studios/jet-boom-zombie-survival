extends StaticBody3D
class_name Barricade

@export var max_health: float = 200.0
@export var repair_cost: int = 10

var current_health: float = 200.0
var is_placed: bool = false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null

signal barricade_destroyed

func _ready():
	add_to_group("barricades")
	current_health = max_health

func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO):
	current_health -= amount
	current_health = max(current_health, 0)

	# Visual feedback for damage
	update_damage_visual()

	if current_health <= 0:
		destroy()

func repair(amount: float = 50.0):
	current_health = min(current_health + amount, max_health)
	update_damage_visual()

func update_damage_visual():
	# Change material or color based on health percentage
	if mesh_instance:
		var health_percent = current_health / max_health
		var mat = StandardMaterial3D.new()
		if health_percent > 0.66:
			mat.albedo_color = Color(0.6, 0.4, 0.2)  # Brown
		elif health_percent > 0.33:
			mat.albedo_color = Color(0.5, 0.3, 0.1)  # Darker brown
		else:
			mat.albedo_color = Color(0.3, 0.2, 0.1)  # Almost broken
		mesh_instance.material_override = mat

func destroy():
	barricade_destroyed.emit()
	queue_free()

func interact(player: Player):
	# Allow player to repair barricade
	if current_health < max_health:
		# Check if player has repair materials
		repair(50.0)
