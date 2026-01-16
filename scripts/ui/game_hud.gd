extends CanvasLayer
class_name GameHUD

## Main game HUD with minimap, health, stamina, survival stats, buffs, weapon info, and hotbar

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

# Survival UI elements (created dynamically)
var survival_panel: Control = null
var hunger_bar: ProgressBar = null
var thirst_bar: ProgressBar = null
var temperature_bar: ProgressBar = null
var weather_label: Label = null
var hazard_warning: Label = null

var player: Node = null
var skill_system: Node = null
var sigil_system: Node = null
var inventory_system: Node = null
var survival_system: Node = null

# Hotbar slots
var hotbar_slots: Array = []
var selected_hotbar_slot: int = 0

func _ready():
	skill_system = get_node_or_null("/root/SkillSystem")
	sigil_system = get_node_or_null("/root/SigilDefenseSystem")
	inventory_system = get_node_or_null("/root/InventorySystem")
	survival_system = get_node_or_null("/root/SurvivalSystem")

	_setup_hotbar()
	_setup_survival_ui()
	_connect_signals()
	if extraction_panel:
		extraction_panel.visible = false

func _setup_hotbar():
	if not hotbar_container:
		return
	for i in range(4):
		var slot = _create_hotbar_slot(i)
		hotbar_container.add_child(slot)
		hotbar_slots.append(slot)
	_select_hotbar_slot(0)

func _setup_survival_ui():
	# Create survival panel in top-right corner
	survival_panel = Panel.new()
	survival_panel.name = "SurvivalPanel"
	survival_panel.custom_minimum_size = Vector2(200, 120)
	survival_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	survival_panel.offset_left = -220
	survival_panel.offset_top = 10
	survival_panel.offset_right = -10
	survival_panel.offset_bottom = 130
	add_child(survival_panel)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	survival_panel.add_child(vbox)

	# Hunger bar
	var hunger_container = _create_survival_bar("Hunger", Color(0.9, 0.6, 0.2))
	vbox.add_child(hunger_container)
	hunger_bar = hunger_container.get_node("Bar")

	# Thirst bar
	var thirst_container = _create_survival_bar("Thirst", Color(0.3, 0.6, 1.0))
	vbox.add_child(thirst_container)
	thirst_bar = thirst_container.get_node("Bar")

	# Temperature bar
	var temp_container = _create_survival_bar("Temp", Color(0.8, 0.4, 0.4))
	vbox.add_child(temp_container)
	temperature_bar = temp_container.get_node("Bar")
	temperature_bar.min_value = -30
	temperature_bar.max_value = 50
	temperature_bar.value = 20  # Normal body temp

	# Weather label
	weather_label = Label.new()
	weather_label.name = "WeatherLabel"
	weather_label.text = "Weather: Clear"
	weather_label.add_theme_font_size_override("font_size", 12)
	weather_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(weather_label)

	# Hazard warning (hidden by default)
	hazard_warning = Label.new()
	hazard_warning.name = "HazardWarning"
	hazard_warning.text = ""
	hazard_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hazard_warning.add_theme_font_size_override("font_size", 16)
	hazard_warning.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	hazard_warning.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hazard_warning.offset_top = 60
	hazard_warning.visible = false
	add_child(hazard_warning)

	# Connect survival system signals
	if survival_system:
		if survival_system.has_signal("weather_changed"):
			survival_system.weather_changed.connect(_on_weather_changed)
		if survival_system.has_signal("hazard_entered"):
			survival_system.hazard_entered.connect(_on_hazard_entered)
		if survival_system.has_signal("hazard_exited"):
			survival_system.hazard_exited.connect(_on_hazard_exited)
		if survival_system.has_signal("player_hunger_critical"):
			survival_system.player_hunger_critical.connect(_on_hunger_critical)
		if survival_system.has_signal("player_thirst_critical"):
			survival_system.player_thirst_critical.connect(_on_thirst_critical)

func _create_survival_bar(label_text: String, bar_color: Color) -> Control:
	var container = HBoxContainer.new()
	container.name = label_text + "Container"

	var label = Label.new()
	label.name = "Label"
	label.text = label_text + ":"
	label.custom_minimum_size = Vector2(50, 0)
	label.add_theme_font_size_override("font_size", 12)
	container.add_child(label)

	var bar = ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(120, 16)
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false

	# Style the bar
	var style = StyleBoxFlat.new()
	style.bg_color = bar_color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", style)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_left = 3
	bg_style.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bg_style)

	container.add_child(bar)
	return container

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
		if player.has_signal("hunger_changed"):
			player.hunger_changed.connect(_on_hunger_changed_signal)
		if player.has_signal("thirst_changed"):
			player.thirst_changed.connect(_on_thirst_changed_signal)
		if player.has_signal("died"):
			player.died.connect(_on_player_died)
		_update_health_display()
		_update_stamina_display()
		_update_survival_display()

func _on_hunger_changed_signal(_old_value: float, new_value: float):
	if hunger_bar:
		hunger_bar.value = new_value

func _on_thirst_changed_signal(_old_value: float, new_value: float):
	if thirst_bar:
		thirst_bar.value = new_value

func _on_player_died(_killer_name: String):
	# Could show death screen overlay
	pass

func _process(_delta):
	_update_minimap()
	_update_survival_display()

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
# SURVIVAL STATS
# ============================================

func _update_survival_display():
	if not player or not survival_system:
		return

	var peer_id = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else multiplayer.get_unique_id()

	if survival_system.has_method("get_player_survival_data"):
		var data = survival_system.get_player_survival_data(peer_id)

		if hunger_bar:
			hunger_bar.value = data.get("hunger", 100.0)
			# Color change when low
			var hunger_style = hunger_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if hunger_style:
				if data.get("hunger", 100.0) < 25:
					hunger_style.bg_color = Color(1.0, 0.2, 0.2)  # Red when critical
				else:
					hunger_style.bg_color = Color(0.9, 0.6, 0.2)

		if thirst_bar:
			thirst_bar.value = data.get("thirst", 100.0)
			var thirst_style = thirst_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if thirst_style:
				if data.get("thirst", 100.0) < 25:
					thirst_style.bg_color = Color(1.0, 0.2, 0.2)
				else:
					thirst_style.bg_color = Color(0.3, 0.6, 1.0)

		if temperature_bar:
			var temp = data.get("body_temperature", 20.0)
			temperature_bar.value = temp
			# Update color based on temperature
			var temp_style = temperature_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if temp_style:
				if temp < 0:
					temp_style.bg_color = Color(0.3, 0.5, 1.0)  # Cold - blue
				elif temp > 35:
					temp_style.bg_color = Color(1.0, 0.4, 0.2)  # Hot - orange/red
				else:
					temp_style.bg_color = Color(0.4, 0.8, 0.4)  # Normal - green

func _on_weather_changed(weather_type: String):
	if weather_label and survival_system:
		var weather_data = {}
		if survival_system.has_method("get_weather_data"):
			weather_data = survival_system.get_weather_data()
		var weather_name = weather_data.get("name", weather_type.capitalize())
		weather_label.text = "Weather: %s" % weather_name

func _on_hazard_entered(p: Node, hazard_type: String):
	if p != player:
		return
	if hazard_warning:
		var hazard_data = {}
		if survival_system and survival_system.has_method("get_hazard_data"):
			hazard_data = survival_system.get_hazard_data(hazard_type)
		hazard_warning.text = hazard_data.get("warning_message", "Warning: Hazard zone!")
		hazard_warning.visible = true
		# Flash effect
		_flash_warning()

func _on_hazard_exited(p: Node, _hazard_type: String):
	if p != player:
		return
	# Check if player is still in any hazards
	if survival_system and survival_system.has_method("get_player_hazards"):
		var peer_id = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else multiplayer.get_unique_id()
		var hazards = survival_system.get_player_hazards(peer_id)
		if hazards.is_empty() and hazard_warning:
			hazard_warning.visible = false

func _on_hunger_critical(p: Node):
	if p != player:
		return
	_show_status_warning("Low hunger! Find food!")

func _on_thirst_critical(p: Node):
	if p != player:
		return
	_show_status_warning("Low thirst! Find water!")

func _flash_warning():
	if not hazard_warning:
		return
	var tween = create_tween()
	tween.set_loops(3)
	tween.tween_property(hazard_warning, "modulate:a", 0.3, 0.3)
	tween.tween_property(hazard_warning, "modulate:a", 1.0, 0.3)

func _show_status_warning(message: String):
	if hazard_warning:
		hazard_warning.text = message
		hazard_warning.visible = true
		var tween = create_tween()
		tween.tween_interval(3.0)
		tween.tween_callback(func(): hazard_warning.visible = false)

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
	if peer_id == multiplayer.get_unique_id() and extraction_panel:
		extraction_panel.visible = true
		_animate_extraction_progress()

func _on_extraction_completed(peer_id: int):
	if peer_id == multiplayer.get_unique_id() and extraction_panel:
		extraction_panel.visible = false

func _on_extraction_cancelled(peer_id: int):
	if peer_id == multiplayer.get_unique_id() and extraction_panel:
		extraction_panel.visible = false

func _animate_extraction_progress():
	if not extraction_progress:
		return
	extraction_progress.value = 0
	var tween = create_tween()
	tween.tween_property(extraction_progress, "value", 100, 15.0)
