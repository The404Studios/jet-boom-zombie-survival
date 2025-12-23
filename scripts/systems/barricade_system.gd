extends Node3D

# Barricade that can be built and repaired
# JetBoom-style nailing mechanic

@export var max_health: float = 100.0
@export var nail_health: float = 20.0
@export var nails_required: int = 6
@export var cost_to_build: int = 50

var current_health: float = 0.0
var nails_placed: int = 0
var is_built: bool = false
var is_being_nailed: bool = false

signal barricade_built
signal barricade_destroyed

func interact(player: Node):
	if not is_built:
		_start_build(player)
	elif current_health < max_health:
		_start_repair(player)

func _start_build(player: Node):
	is_being_nailed = true
	nails_placed = 0
	
	for i in range(nails_required):
		await get_tree().create_timer(0.5).timeout
		nails_placed += 1
		current_health += nail_health
		
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sound_3d("hammer", global_position)
	
	is_built = true
	barricade_built.emit()

func take_damage(amount: float):
	current_health -= amount
	if current_health <= 0:
		queue_free()
		barricade_destroyed.emit()
