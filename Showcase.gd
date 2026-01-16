extends Node3D

## Showcase scene controller for Free_Character demo
## Displays character models in a rotating showcase

@export var rotation_speed: float = 30.0
@export var auto_rotate: bool = true

var current_character_index: int = 0
var characters: Array = []

func _ready():
	# Find all character models
	for child in get_children():
		if child is Node3D and child.name.begins_with("Character"):
			characters.append(child)
			child.visible = false

	# Show first character
	if characters.size() > 0:
		characters[0].visible = true

func _process(delta):
	if auto_rotate:
		rotation_degrees.y += rotation_speed * delta

func _input(event):
	if event.is_action_pressed("ui_right"):
		next_character()
	elif event.is_action_pressed("ui_left"):
		previous_character()

func next_character():
	if characters.size() == 0:
		return

	characters[current_character_index].visible = false
	current_character_index = (current_character_index + 1) % characters.size()
	characters[current_character_index].visible = true

func previous_character():
	if characters.size() == 0:
		return

	characters[current_character_index].visible = false
	current_character_index = (current_character_index - 1 + characters.size()) % characters.size()
	characters[current_character_index].visible = true
