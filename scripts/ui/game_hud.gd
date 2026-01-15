extends CanvasLayer
class_name GameHUD

## Main game HUD with minimap, health, stamina, buffs, weapon info, and hotbar

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthStaminaPanel/HealthBar
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthStaminaPanel/StaminaBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthStaminaPanel/HealthLabel
@onready var minimap: Control = $MinimapContainer/Minimap
@onready var buff_container: HBoxContainer = $MarginContainer/VBoxContainer/BuffContainer
@onready var ammo_label: Label = $WeaponPanel/AmmoLabel
@onready var weapon_name_label: Label = $WeaponPanel/WeaponName
@onready var hotbar_container: HBoxContainer = $HotbarPanel/HotbarContainer
@onready var wave_label: Label = $WavePanel/WaveLabel
@onready var sigil_health_bar: ProgressBar = $SigilPanel/SigilHealthBar
@onready var extraction_panel: Control = $ExtractionPanel
@onready var extraction_progress: ProgressBar = $ExtractionPanel/ExtractionProgress

var player: Node = null
var skill_system: Node = null
var sigil_system: Node = null
var inventory_system: Node = null

# Hotbar slots
var hotbar_slots: Array = []
var selected_hotbar_slot: int = 0

func _ready():
	skill_system = get_node_or_null("/root/SkillSystem")
	sigil_system = get_node_or_null("/root/SigilDefenseSystem")
	inventory_system = get_node_or_null("/root/InventorySystem")
	
	_setup_hotbar()
	_connect_signals()
	extraction_panel.visible = false

func _setup_hotbar():
	for i in range(4):
		var slot = _create_hotbar_slot(i)
		hotbar_container.add_child(slot)
		hotbar_slots.append(slot)
	_select_hotbar_slot(0)

func _create_hotbar_slot(index: int) -> Control:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(64, 64)
	slot.name = "Slot_%d" % index
	
	var label = Label.new()
	label.name = "KeyLabel"
	label.text = str(index + 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	slot.add_child(label)
	
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(48, 48)
	icon.position = Vector2(8, 8)
	slot.add_child(icon)
	
	return slot

func _connect_signals():
	if sigil_system:
		if sigil_system.has_signal("sigil_damaged"):
			sigil_system.sigil_damaged.connect(_on_sigil_damaged)
		if sigil_system.has_signal("round_started"):
			sigil_system.round_started.connect(_on_round_started)
		if sigil_system.has_signal("extraction_available"):
			sigil_system.extraction_available.connect(_on_extraction_available)
		if sigil_system.has_signal("extraction_started"):
			sigil_system.extraction_started.connect(_on_extraction_started)
		if sigil_system.has_signal("extraction_completed"):
			sigil_system.extraction_completed.connect(_on_extraction_completed)
		if sigil_system.has_signal("extraction_cancelled"):
			sigil_system.extraction_cancelled.connect(_on_extraction_cancelled)

func set_player(p: Node):
	player = p
	if player:
		if player.has_signal("health_changed"):
			player.health_changed.connect(_on_health_changed)
		if player.has_signal("stamina_changed"):
			player.stamina_changed.connect(_on_stamina_changed)
		if player.has_signal("weapon_changed"):
			player.weapon_changed.connect(_on_weapon_changed)
		if player.has_signal("ammo_changed"):
			player.ammo_changed.connect(_on_ammo_changed)
		_update_health_display()
		_update_stamina_display()

func _process(_delta):
	_update_minimap()

# ============================================
# HEALTH & STAMINA
# ============================================

func _on_health_changed(current_or_old: float, new_or_max: float):
	# Handle both signal formats:
	# - PlayerController emits (old_value, new_value)
	# - FPSController emits (current, max)
	# Use whichever makes sense - if second param > 100, it's likely max health
	var current_value = current_or_old
	if new_or_max <= 100 and new_or_max != current_or_old:
		# Likely (old, new) format
		current_value = new_or_max

	if health_bar:
		var max_hp = player.max_health if player else 100.0
		if skill_system:
			max_hp += skill_system.get_attribute("max_health")
		health_bar.max_value = max_hp
		health_bar.value = current_value
	if health_label:
		health_label.text = "%.0f" % current_value

func _on_stamina_changed(current_or_old: float, new_or_max: float):
	# Handle both signal formats
	var current_value = current_or_old
	if new_or_max <= 100 and new_or_max != current_or_old:
		current_value = new_or_max

	if stamina_bar:
		var max_stam = player.max_stamina if player else 100.0
		if skill_system:
			max_stam += skill_system.get_attribute("max_stamina")
		stamina_bar.max_value = max_stam
		stamina_bar.value = current_value

func _update_health_display():
	if player and health_bar:
		var max_hp = player.max_health
		if skill_system:
			max_hp += skill_system.get_attribute("max_health")
		health_bar.max_value = max_hp
		health_bar.value = player.current_health

func _update_stamina_display():
	if player and stamina_bar:
		var max_stam = player.max_stamina
		if skill_system:
			max_stam += skill_system.get_attribute("max_stamina")
		stamina_bar.max_value = max_stam
		stamina_bar.value = player.current_stamina

# ============================================
# WEAPON & AMMO
# ============================================

func _on_weapon_changed(index: int):
	_select_hotbar_slot(index)
	if player and "current_weapon" in player and player.current_weapon:
		if weapon_name_label:
			weapon_name_label.text = player.current_weapon.weapon_name if "weapon_name" in player.current_weapon else "Unknown"

func _on_ammo_changed(current: int, reserve: int):
	if ammo_label:
		ammo_label.text = "%d/%d" % [current, reserve]

func _select_hotbar_slot(index: int):
	for i in range(hotbar_slots.size()):
		var slot = hotbar_slots[i]
		if i == index:
			slot.modulate = Color(1.2, 1.2, 1.2)
		else:
			slot.modulate = Color(0.7, 0.7, 0.7)
	selected_hotbar_slot = index

# ============================================
# BUFFS
# ============================================

func add_buff(buff_name: String, icon: Texture2D, duration: float):
	var buff_panel = Panel.new()
	buff_panel.custom_minimum_size = Vector2(32, 32)
	buff_panel.name = buff_name
	
	var icon_rect = TextureRect.new()
	icon_rect.texture = icon
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	buff_panel.add_child(icon_rect)
	
	buff_container.add_child(buff_panel)
	
	if duration > 0:
		await get_tree().create_timer(duration).timeout
		if is_instance_valid(buff_panel):
			buff_panel.queue_free()

func remove_buff(buff_name: String):
	var buff = buff_container.get_node_or_null(buff_name)
	if buff:
		buff.queue_free()

# ============================================
# MINIMAP
# ============================================

func _update_minimap():
	# Update minimap with player positions, zombies, objectives
	pass

# ============================================
# WAVE & SIGIL
# ============================================

func _on_sigil_damaged(_damage: float, health: float):
	if sigil_health_bar and sigil_system:
		sigil_health_bar.value = health / sigil_system.sigil_max_health * 100.0

func _on_round_started(round_num: int):
	if wave_label:
		wave_label.text = "Wave %d" % round_num

# ============================================
# EXTRACTION
# ============================================

func _on_extraction_available(_pos: Vector3):
	# Show extraction indicator
	pass

func _on_extraction_started(peer_id: int):
	if peer_id == multiplayer.get_unique_id():
		extraction_panel.visible = true
		_animate_extraction_progress()

func _on_extraction_completed(peer_id: int):
	if peer_id == multiplayer.get_unique_id():
		extraction_panel.visible = false

func _on_extraction_cancelled(peer_id: int):
	if peer_id == multiplayer.get_unique_id():
		extraction_panel.visible = false

func _animate_extraction_progress():
	extraction_progress.value = 0
	var tween = create_tween()
	tween.tween_property(extraction_progress, "value", 100, 15.0)
