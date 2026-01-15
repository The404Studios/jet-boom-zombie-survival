extends Area3D
class_name HazardZone

## Environmental Hazard Zone
## Creates dangerous areas that apply status effects and damage to players

signal player_entered_zone(player: Node)
signal player_exited_zone(player: Node)

@export_enum("radiation", "toxic_gas", "fire", "cold", "acid", "darkness") var hazard_type: String = "radiation"
@export var damage_multiplier: float = 1.0
@export var zone_radius: float = 5.0
@export var zone_height: float = 3.0
@export var show_visual_effect: bool = true
@export var pulse_effect: bool = true

var survival_system: Node = null
var players_in_zone: Array[Node] = []
var hazard_data: Dictionary = {}

# Visual components
var visual_mesh: MeshInstance3D = null
var effect_material: ShaderMaterial = null

func _ready():
	survival_system = get_node_or_null("/root/SurvivalSystem")

	# Get hazard data from survival system
	if survival_system and survival_system.has_method("get_hazard_data"):
		hazard_data = survival_system.get_hazard_data(hazard_type)

	# Setup collision shape
	_setup_collision()

	# Setup visual effect
	if show_visual_effect:
		_setup_visual()

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Register with survival system
	if survival_system and survival_system.has_method("register_hazard_zone"):
		survival_system.register_hazard_zone(self)

func _exit_tree():
	# Unregister from survival system
	if survival_system and survival_system.has_method("unregister_hazard_zone"):
		survival_system.unregister_hazard_zone(self)

func _setup_collision():
	# Create or update collision shape
	var collision = get_node_or_null("CollisionShape3D")
	if not collision:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		add_child(collision)

	var shape = CylinderShape3D.new()
	shape.radius = zone_radius
	shape.height = zone_height
	collision.shape = shape

func _setup_visual():
	# Create visual representation of the hazard zone
	visual_mesh = get_node_or_null("VisualMesh")
	if not visual_mesh:
		visual_mesh = MeshInstance3D.new()
		visual_mesh.name = "VisualMesh"
		add_child(visual_mesh)

	# Create cylinder mesh
	var mesh = CylinderMesh.new()
	mesh.top_radius = zone_radius
	mesh.bottom_radius = zone_radius
	mesh.height = zone_height
	visual_mesh.mesh = mesh

	# Create material with hazard color
	var material = StandardMaterial3D.new()
	var color = hazard_data.get("color", Color(1.0, 0.0, 0.0, 0.3))
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual_mesh.material_override = material

func _process(delta):
	# Apply hazard effects to all players in zone
	for player in players_in_zone:
		if is_instance_valid(player):
			_apply_hazard_effect(player, delta)

	# Pulse visual effect
	if pulse_effect and visual_mesh:
		var pulse = 0.8 + sin(Time.get_ticks_msec() * 0.003) * 0.2
		var mat = visual_mesh.material_override as StandardMaterial3D
		if mat:
			var base_color = hazard_data.get("color", Color(1.0, 0.0, 0.0, 0.3))
			mat.albedo_color.a = base_color.a * pulse

func _apply_hazard_effect(player: Node, delta: float):
	# Apply damage
	if survival_system and survival_system.has_method("apply_hazard_damage"):
		survival_system.apply_hazard_damage(player, hazard_type, delta * damage_multiplier)

func _on_body_entered(body: Node):
	if not body.is_in_group("player"):
		return

	if body not in players_in_zone:
		players_in_zone.append(body)
		player_entered_zone.emit(body)

		# Notify survival system
		if survival_system and survival_system.has_method("player_entered_hazard"):
			survival_system.player_entered_hazard(body, hazard_type)

		# Show warning message
		_show_warning(body)

func _on_body_exited(body: Node):
	if body in players_in_zone:
		players_in_zone.erase(body)
		player_exited_zone.emit(body)

		# Notify survival system
		if survival_system and survival_system.has_method("player_exited_hazard"):
			survival_system.player_exited_hazard(body, hazard_type)

func _show_warning(player: Node):
	# Show warning message to player
	var message = hazard_data.get("warning_message", "Warning: Hazard zone!")

	# Try to show via HUD or chat
	var game_ui = get_node_or_null("/root/GameUI")
	if game_ui and game_ui.has_method("show_warning"):
		game_ui.show_warning(message)

	# Or via EventBus
	var event_bus = get_node_or_null("/root/EventBus")
	if event_bus and event_bus.has_method("emit"):
		event_bus.emit("show_warning", {"message": message, "player": player})

# ============================================
# PUBLIC API
# ============================================

func set_hazard_type(new_type: String):
	"""Change the hazard type"""
	hazard_type = new_type
	if survival_system and survival_system.has_method("get_hazard_data"):
		hazard_data = survival_system.get_hazard_data(hazard_type)
	if show_visual_effect:
		_setup_visual()

func set_zone_size(radius: float, height: float):
	"""Change the zone size"""
	zone_radius = radius
	zone_height = height
	_setup_collision()
	if show_visual_effect:
		_setup_visual()

func get_players_in_zone() -> Array[Node]:
	"""Get all players currently in this zone"""
	return players_in_zone.duplicate()

func is_player_inside(player: Node) -> bool:
	"""Check if a specific player is in this zone"""
	return player in players_in_zone
