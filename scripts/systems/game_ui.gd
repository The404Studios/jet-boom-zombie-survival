extends Control
class_name GameUI

@onready var health_bar: ProgressBar = $HUD/HealthBar if has_node("HUD/HealthBar") else null
@onready var stamina_bar: ProgressBar = $HUD/StaminaBar if has_node("HUD/StaminaBar") else null
@onready var ammo_label: Label = $HUD/AmmoLabel if has_node("HUD/AmmoLabel") else null
@onready var interact_prompt: Label = $HUD/InteractPrompt if has_node("HUD/InteractPrompt") else null
@onready var inventory_panel: Panel = $InventoryPanel if has_node("InventoryPanel") else null
@onready var crosshair: Control = $HUD/Crosshair if has_node("HUD/Crosshair") else null

var player: Node = null  # Player type - use Node for load order safety
var inventory_open: bool = false

func _ready():
	if inventory_panel:
		inventory_panel.visible = false

func setup(p: Node):  # p: Player
	player = p
	if player:
		player.health_changed.connect(_on_health_changed)
		player.stamina_changed.connect(_on_stamina_changed)

func _on_health_changed(current: float, maximum: float):
	if health_bar:
		health_bar.max_value = maximum
		health_bar.value = current

func _on_stamina_changed(current: float, maximum: float):
	if stamina_bar:
		stamina_bar.max_value = maximum
		stamina_bar.value = current

func update_ammo(current: int, total: int):
	if ammo_label:
		ammo_label.text = "%d / %d" % [current, total]

func show_interact_prompt(text: String):
	if interact_prompt:
		interact_prompt.text = text
		interact_prompt.visible = true

func hide_interact_prompt():
	if interact_prompt:
		interact_prompt.visible = false

func toggle_inventory():
	inventory_open = !inventory_open
	if inventory_panel:
		inventory_panel.visible = inventory_open

func is_inventory_open() -> bool:
	return inventory_open
