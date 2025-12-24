extends Area3D
class_name LootItem

var item_data: ItemData = null
var item_mesh: MeshInstance3D = null

@onready var label: Label3D = $Label3D if has_node("Label3D") else null

func _ready():
	add_to_group("loot")
	body_entered.connect(_on_body_entered)

func set_item_data(data: ItemData):
	item_data = data

	# Update visual
	if item_data.mesh_scene:
		if item_mesh:
			item_mesh.queue_free()
		item_mesh = item_data.mesh_scene.instantiate()
		add_child(item_mesh)

	# Update label
	if label:
		label.text = item_data.item_name

func get_item_data() -> ItemData:
	return item_data

func _on_body_entered(body: Node3D):
	if body is Player:
		interact(body)

func interact(player: Player):
	if item_data and player.inventory.add_item(item_data, 1):
		queue_free()
