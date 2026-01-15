extends RigidBody3D
class_name ConsumableItem

## Consumable item that can be picked up and used by players
## Restores hunger, thirst, health, or stamina

signal consumed(player: Node)
signal picked_up(player: Node)

# Item data
@export var item_id: String = ""
@export var item_name: String = "Unknown Item"
@export var item_type: String = "food"  # food, water, health, stamina
@export var restore_value: float = 25.0
@export var use_time: float = 2.0
@export var item_weight: float = 0.5

# Bonus effects
@export var bonus_food: float = 0.0
@export var bonus_water: float = 0.0
@export var bonus_stamina: float = 0.0
@export var bonus_health: float = 0.0

# Visual
@export var item_color: Color = Color.WHITE
@export var glow_intensity: float = 0.3

# State
var is_being_consumed: bool = false
var consume_progress: float = 0.0
var consumer: Node = null

# References
@onready var mesh: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var collision: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null
@onready var interact_area: Area3D = $InteractArea if has_node("InteractArea") else null
@onready var label: Label3D = $Label3D if has_node("Label3D") else null
@onready var particles: GPUParticles3D = $Particles if has_node("Particles") else null

func _ready():
	add_to_group("consumables")
	add_to_group("interactables")

	# Setup collision layers
	collision_layer = 8  # Items layer
	collision_mask = 1   # Environment

	# Apply visual style based on type
	_apply_visual_style()

	# Setup interact area if it exists
	if interact_area:
		interact_area.body_entered.connect(_on_body_entered)

	# Create label if missing
	if not label:
		_create_floating_label()

func _process(delta):
	# Handle consumption progress
	if is_being_consumed and consumer:
		consume_progress += delta
		if consume_progress >= use_time:
			_complete_consumption()

	# Floating bob animation
	if mesh:
		mesh.position.y = sin(Time.get_ticks_msec() * 0.003) * 0.05 + 0.15

	# Rotate slowly
	rotation.y += delta * 0.5

func setup(id: String, data: Dictionary):
	"""Setup item from survival system data"""
	item_id = id
	item_name = data.get("name", "Unknown")
	item_type = data.get("type", "food")
	restore_value = data.get("value", 25.0)
	use_time = data.get("use_time", 2.0)
	item_weight = data.get("weight", 0.5)

	bonus_food = data.get("bonus_food", 0.0)
	bonus_water = data.get("bonus_water", 0.0)
	bonus_stamina = data.get("bonus_stamina", 0.0)
	bonus_health = data.get("bonus_health", 0.0)

	_apply_visual_style()

	if label:
		label.text = item_name

func _apply_visual_style():
	"""Apply visual style based on item type"""
	if not mesh:
		return

	var mat = StandardMaterial3D.new()

	match item_type:
		"food":
			mat.albedo_color = Color(0.8, 0.6, 0.3)  # Brown/tan
			item_color = Color(0.9, 0.7, 0.4)
		"water":
			mat.albedo_color = Color(0.3, 0.6, 0.9)  # Blue
			item_color = Color(0.4, 0.7, 1.0)
		"health":
			mat.albedo_color = Color(0.9, 0.3, 0.3)  # Red
			item_color = Color(1.0, 0.4, 0.4)
		"stamina":
			mat.albedo_color = Color(0.3, 0.9, 0.5)  # Green
			item_color = Color(0.4, 1.0, 0.6)
		_:
			mat.albedo_color = Color.WHITE

	mat.emission_enabled = true
	mat.emission = item_color
	mat.emission_energy_multiplier = glow_intensity

	mesh.material_override = mat

func _create_floating_label():
	"""Create a floating label for the item"""
	label = Label3D.new()
	label.text = item_name
	label.font_size = 24
	label.position = Vector3(0, 0.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = item_color
	add_child(label)

# ============================================
# INTERACTION
# ============================================

func interact(player: Node) -> bool:
	"""Called when player presses interact"""
	if is_being_consumed:
		return false

	# Start consumption
	return start_consume(player)

func start_consume(player: Node) -> bool:
	"""Start consuming this item"""
	if is_being_consumed:
		return false

	is_being_consumed = true
	consume_progress = 0.0
	consumer = player

	# Show consumption UI
	_show_consume_progress()

	return true

func cancel_consume():
	"""Cancel consumption in progress"""
	is_being_consumed = false
	consume_progress = 0.0
	consumer = null

	_hide_consume_progress()

func _complete_consumption():
	"""Complete the consumption and apply effects"""
	if not consumer:
		return

	# Apply main effect
	match item_type:
		"food":
			if consumer.has_method("consume_food"):
				consumer.consume_food(restore_value)
		"water":
			if consumer.has_method("consume_water"):
				consumer.consume_water(restore_value)
		"health":
			if consumer.has_method("heal"):
				consumer.heal(restore_value)
		"stamina":
			if consumer.has_method("consume_item"):
				consumer.consume_item("stamina", restore_value)

	# Apply bonus effects
	if bonus_food > 0 and consumer.has_method("consume_food"):
		consumer.consume_food(bonus_food)
	if bonus_water > 0 and consumer.has_method("consume_water"):
		consumer.consume_water(bonus_water)
	if bonus_stamina > 0 and consumer.has_method("consume_item"):
		consumer.consume_item("stamina", bonus_stamina)
	if bonus_health > 0 and consumer.has_method("heal"):
		consumer.heal(bonus_health)

	# Emit signals
	consumed.emit(consumer)

	# Play effects
	_play_consume_effect()

	# Remove item
	queue_free()

func consume(player: Node) -> bool:
	"""Instant consume (for quick pickup)"""
	consumer = player
	_complete_consumption()
	return true

# ============================================
# VISUAL FEEDBACK
# ============================================

func _show_consume_progress():
	"""Show consumption progress indicator"""
	# Could show a progress bar above the item
	if label:
		label.text = item_name + "\n[Consuming...]"

func _hide_consume_progress():
	"""Hide consumption progress indicator"""
	if label:
		label.text = item_name

func _play_consume_effect():
	"""Play consumption visual/audio effect"""
	# Spawn particles
	if particles:
		particles.emitting = true

	# Play sound via AudioManager
	var audio = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sound_3d"):
		match item_type:
			"food":
				audio.play_sound_3d("eat", global_position, 0.8)
			"water":
				audio.play_sound_3d("drink", global_position, 0.8)
			"health":
				audio.play_sound_3d("heal", global_position, 0.8)
			"stamina":
				audio.play_sound_3d("powerup", global_position, 0.8)

func _on_body_entered(body: Node3D):
	"""Handle collision with player for auto-pickup"""
	if body.is_in_group("player"):
		# Could implement auto-pickup here
		pass

# ============================================
# UTILITY
# ============================================

func get_display_name() -> String:
	return item_name

func get_description() -> String:
	var desc = ""
	match item_type:
		"food":
			desc = "Restores %d hunger" % int(restore_value)
		"water":
			desc = "Restores %d thirst" % int(restore_value)
		"health":
			desc = "Restores %d health" % int(restore_value)
		"stamina":
			desc = "Restores %d stamina" % int(restore_value)

	if bonus_food > 0:
		desc += "\n+%d hunger" % int(bonus_food)
	if bonus_water > 0:
		desc += "\n+%d thirst" % int(bonus_water)
	if bonus_stamina > 0:
		desc += "\n+%d stamina" % int(bonus_stamina)
	if bonus_health > 0:
		desc += "\n+%d health" % int(bonus_health)

	return desc

func get_weight() -> float:
	return item_weight

func get_consume_time() -> float:
	return use_time
