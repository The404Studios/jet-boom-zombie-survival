extends Control
class_name CharacterSelectPanel

signal character_selected(character_id: String)
signal panel_closed
signal continue_pressed

# Character data
const CHARACTERS = {
	"dizzy": {
		"name": "Dizzy",
		"description": "Street-smart survivor with agility bonus",
		"model_path": "res://Free_Character/ShowcaseFreeCharacter/Characters/Street/Dizzy.glb",
		"stats": {"health": 100, "speed": 1.2, "damage": 1.0}
	},
	"piggy": {
		"name": "Piggy",
		"description": "Tough survivor with extra health",
		"model_path": "res://Free_Character/ShowcaseFreeCharacter/Characters/NWorld/Piggy.glb",
		"stats": {"health": 150, "speed": 0.9, "damage": 1.0}
	},
	"popcorn": {
		"name": "Popcorn",
		"description": "Balanced survivor, jack of all trades",
		"model_path": "res://Free_Character/ShowcaseFreeCharacter/Characters/Popcorn/Popcorn.glb",
		"stats": {"health": 100, "speed": 1.0, "damage": 1.1}
	},
	"spawn": {
		"name": "Spawn",
		"description": "Mysterious survivor with damage bonus",
		"model_path": "res://Free_Character/ShowcaseFreeCharacter/Characters/Under/Spawn.glb",
		"stats": {"health": 90, "speed": 1.1, "damage": 1.3}
	},
	"nanzy": {
		"name": "Nanzy",
		"description": "Quick and nimble survivor",
		"model_path": "res://Free_Character/ShowcaseFreeCharacter/Characters/Popcorn/Nanzy.glb",
		"stats": {"health": 85, "speed": 1.3, "damage": 0.9}
	}
}

@onready var viewport: SubViewport = $PreviewContainer/SubViewport
@onready var camera: Camera3D = $PreviewContainer/SubViewport/Camera3D
@onready var character_holder: Node3D = $PreviewContainer/SubViewport/CharacterHolder
@onready var character_name_label: Label = $InfoPanel/CharacterName
@onready var description_label: Label = $InfoPanel/Description
@onready var health_bar: ProgressBar = $InfoPanel/StatsContainer/HealthBar
@onready var speed_bar: ProgressBar = $InfoPanel/StatsContainer/SpeedBar
@onready var damage_bar: ProgressBar = $InfoPanel/StatsContainer/DamageBar
@onready var prev_btn: Button = $SelectionContainer/PrevButton
@onready var next_btn: Button = $SelectionContainer/NextButton
@onready var continue_btn: Button = $ContinueButton
@onready var close_btn: Button = $CloseButton

var character_keys: Array = []
var current_index: int = 0
var current_model: Node3D = null
var camera_angle: float = 0.0
var camera_distance: float = 3.0
var camera_height: float = 1.5
var rotation_speed: float = 0.5

func _ready():
	character_keys = CHARACTERS.keys()

	# Connect buttons
	if prev_btn:
		prev_btn.pressed.connect(_on_prev_pressed)
	if next_btn:
		next_btn.pressed.connect(_on_next_pressed)
	if continue_btn:
		continue_btn.pressed.connect(_on_continue_pressed)
	if close_btn:
		close_btn.pressed.connect(_on_close_pressed)

	# Load first character
	_load_character(0)

	# Setup initial camera position
	_update_camera_position()

func _process(delta):
	if not visible:
		return

	# Rotate camera around character
	camera_angle += delta * rotation_speed
	if camera_angle > TAU:
		camera_angle -= TAU

	_update_camera_position()

	# Also rotate the model slightly for idle animation feel
	if current_model and is_instance_valid(current_model):
		# Small breathing animation
		var bob = sin(Time.get_ticks_msec() * 0.002) * 0.02
		current_model.position.y = bob

func _update_camera_position():
	if not camera:
		return

	var x = cos(camera_angle) * camera_distance
	var z = sin(camera_angle) * camera_distance
	camera.position = Vector3(x, camera_height, z)
	camera.look_at(Vector3(0, 1, 0), Vector3.UP)

func _on_prev_pressed():
	current_index -= 1
	if current_index < 0:
		current_index = character_keys.size() - 1
	_load_character(current_index)

func _on_next_pressed():
	current_index += 1
	if current_index >= character_keys.size():
		current_index = 0
	_load_character(current_index)

func _load_character(index: int):
	var char_id = character_keys[index]
	var char_data = CHARACTERS[char_id]

	# Remove current model
	if current_model and is_instance_valid(current_model):
		current_model.queue_free()
		current_model = null

	# Load new model
	var model_path = char_data["model_path"]
	if ResourceLoader.exists(model_path):
		var model_scene = load(model_path)
		if model_scene:
			current_model = model_scene.instantiate()
			if character_holder:
				character_holder.add_child(current_model)
				# Scale and position the model appropriately
				current_model.scale = Vector3(1, 1, 1)
				current_model.position = Vector3.ZERO
				current_model.rotation = Vector3.ZERO

				# Try to play idle animation if available
				_play_idle_animation(current_model)

	# Update UI
	_update_character_info(char_data)

func _play_idle_animation(model: Node3D):
	# Look for AnimationPlayer in the model
	var anim_player = _find_animation_player(model)
	if anim_player:
		# Try common idle animation names
		var idle_names = ["idle", "Idle", "IDLE", "idle_loop", "stand", "breathing"]
		for anim_name in idle_names:
			if anim_player.has_animation(anim_name):
				anim_player.play(anim_name)
				return

		# Play first animation if no idle found
		var animations = anim_player.get_animation_list()
		if animations.size() > 0:
			anim_player.play(animations[0])

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result

	return null

func _update_character_info(char_data: Dictionary):
	if character_name_label:
		character_name_label.text = char_data["name"]

	if description_label:
		description_label.text = char_data["description"]

	var stats = char_data["stats"]
	if health_bar:
		health_bar.value = stats["health"]
		health_bar.max_value = 150
	if speed_bar:
		speed_bar.value = stats["speed"] * 100
		speed_bar.max_value = 150
	if damage_bar:
		damage_bar.value = stats["damage"] * 100
		damage_bar.max_value = 150

func _on_continue_pressed():
	var selected_id = character_keys[current_index]

	# Save selection to GameSettings
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		settings.set_meta("selected_character", selected_id)

	character_selected.emit(selected_id)
	continue_pressed.emit()

func _on_close_pressed():
	panel_closed.emit()

func get_selected_character() -> String:
	return character_keys[current_index]

func get_selected_character_data() -> Dictionary:
	return CHARACTERS[character_keys[current_index]]
