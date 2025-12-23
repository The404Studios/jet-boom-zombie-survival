extends Node3D
class_name BarricadeSpot

@export var barricade_scene: PackedScene
@export var requires_nails: int = 5

var has_barricade: bool = false
var current_barricade: Barricade = null

@onready var placement_marker: MeshInstance3D = $PlacementMarker if has_node("PlacementMarker") else null

func _ready():
	add_to_group("barricade_spot")

	# Create visual marker
	if not placement_marker:
		placement_marker = MeshInstance3D.new()
		add_child(placement_marker)
		var box = BoxMesh.new()
		box.size = Vector3(2, 2, 0.2)
		placement_marker.mesh = box

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 0, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		placement_marker.material_override = mat

func interact(player: Player):
	if not has_barricade:
		place_barricade(player)
	else:
		repair_barricade(player)

func place_barricade(player: Player):
	# Check if player has nails/materials
	# For now, just place it
	if barricade_scene:
		current_barricade = barricade_scene.instantiate()
		get_parent().add_child(current_barricade)
		current_barricade.global_transform = global_transform
		current_barricade.barricade_destroyed.connect(_on_barricade_destroyed)
		has_barricade = true

		# Hide marker
		if placement_marker:
			placement_marker.visible = false

func repair_barricade(player: Player):
	if current_barricade:
		current_barricade.repair(player)

func _on_barricade_destroyed():
	has_barricade = false
	current_barricade = null

	# Show marker again
	if placement_marker:
		placement_marker.visible = true
