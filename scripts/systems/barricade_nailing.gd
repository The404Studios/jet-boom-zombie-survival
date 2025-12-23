extends Node
class_name BarricadeNailing

# Nailing system like JetBoom's Zombie Survival

signal nailing_started(barricade: Node)
signal nail_placed(barricade: Node, nail_count: int)
signal nailing_completed(barricade: Node)
signal nailing_cancelled

@export var nails_required: int = 6
@export var nail_time: float = 0.5  # Time per nail
@export var nail_range: float = 3.0

var is_nailing: bool = false
var current_barricade: Node = null
var nails_placed: int = 0
var nail_timer: float = 0.0
var player: Node = null

func _ready():
	set_process(false)

func _process(delta):
	if not is_nailing:
		return

	nail_timer -= delta

	if nail_timer <= 0:
		place_nail()
		nail_timer = nail_time

	# Check if player moved too far
	if player and current_barricade:
		var distance = player.global_position.distance_to(current_barricade.global_position)
		if distance > nail_range:
			cancel_nailing()

	# Check if player stopped holding interact
	if not Input.is_action_pressed("interact"):
		cancel_nailing()

func start_nailing(barricade: Node, nailing_player: Node):
	if is_nailing:
		return

	current_barricade = barricade
	player = nailing_player
	is_nailing = true
	nails_placed = 0
	nail_timer = nail_time

	nailing_started.emit(barricade)
	set_process(true)

	print("Started nailing barricade...")

func place_nail():
	if not current_barricade:
		cancel_nailing()
		return

	nails_placed += 1
	nail_placed.emit(current_barricade, nails_placed)

	# Play nail sound
	play_nail_sound()

	# Update barricade health
	if current_barricade.has_method("add_nail"):
		current_barricade.add_nail()

	print("Nail %d/%d placed" % [nails_placed, nails_required])

	# Check if complete
	if nails_placed >= nails_required:
		complete_nailing()

func complete_nailing():
	if not current_barricade:
		return

	# Fully repair/upgrade barricade
	if current_barricade.has_method("complete_repair"):
		current_barricade.complete_repair()

	nailing_completed.emit(current_barricade)

	print("Barricade fully nailed!")

	# Clean up
	is_nailing = false
	current_barricade = null
	player = null
	set_process(false)

func cancel_nailing():
	if not is_nailing:
		return

	print("Nailing cancelled")

	nailing_cancelled.emit()

	is_nailing = false
	current_barricade = null
	player = null
	set_process(false)

func play_nail_sound():
	# Play hammer sound effect through AudioManager autoload
	if current_barricade and has_node("/root/AudioManager"):
		var audio_manager = get_node("/root/AudioManager")
		if audio_manager.has_method("play_sound_3d"):
			audio_manager.play_sound_3d("hammer", current_barricade.global_position)
		elif audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("hammer")

	# Visual feedback - spawn particle effect
	if current_barricade and has_node("/root/VFXManager"):
		var vfx_manager = get_node("/root/VFXManager")
		if vfx_manager.has_method("spawn_impact_effect"):
			var hit_pos = current_barricade.global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.5), randf_range(-0.3, 0.3))
			vfx_manager.spawn_impact_effect(hit_pos, Vector3.UP, "wood")

func get_nail_progress() -> float:
	if nails_required <= 0:
		return 0.0

	return float(nails_placed) / float(nails_required)

func is_currently_nailing() -> bool:
	return is_nailing
