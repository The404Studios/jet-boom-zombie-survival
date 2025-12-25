extends Control
class_name RemantlerPanel

# Remantler UI Panel
# Allows players to upgrade weapons, add augments, and manage equipment

signal panel_closed
signal weapon_upgraded(weapon: Resource)
signal augment_added(weapon: Resource, augment: Resource)

# References
var remantler: RemantlerSystem = null
var sigil_shop: SigilShop = null
var player: Node = null

# UI State
var selected_weapon: Resource = null
var is_open: bool = false

# UI Elements
@onready var panel_container: PanelContainer = $PanelContainer
@onready var close_button: Button = $PanelContainer/VBox/Header/CloseButton
@onready var sigil_label: Label = $PanelContainer/VBox/Header/SigilLabel

# Weapon selection
@onready var weapon_list: ItemList = $PanelContainer/VBox/Content/LeftPanel/WeaponList
@onready var weapon_stats: RichTextLabel = $PanelContainer/VBox/Content/CenterPanel/WeaponStats

# Upgrade panel
@onready var upgrade_button: Button = $PanelContainer/VBox/Content/CenterPanel/UpgradeSection/UpgradeButton
@onready var upgrade_cost_label: Label = $PanelContainer/VBox/Content/CenterPanel/UpgradeSection/CostLabel
@onready var upgrade_preview: RichTextLabel = $PanelContainer/VBox/Content/CenterPanel/UpgradeSection/PreviewLabel
@onready var materials_label: RichTextLabel = $PanelContainer/VBox/Content/CenterPanel/UpgradeSection/MaterialsLabel

# Augment panel
@onready var augment_list: ItemList = $PanelContainer/VBox/Content/RightPanel/AugmentList
@onready var add_augment_button: Button = $PanelContainer/VBox/Content/RightPanel/AddAugmentButton

# Dismantle panel
@onready var dismantle_button: Button = $PanelContainer/VBox/Content/CenterPanel/DismantleSection/DismantleButton
@onready var dismantle_preview: Label = $PanelContainer/VBox/Content/CenterPanel/DismantleSection/PreviewLabel

# Reroll panel
@onready var reroll_button: Button = $PanelContainer/VBox/Content/CenterPanel/RerollSection/RerollButton
@onready var reroll_cost_label: Label = $PanelContainer/VBox/Content/CenterPanel/RerollSection/CostLabel

func _ready():
	visible = false

	# Connect signals
	_connect_ui_signals()

	# Find systems
	await get_tree().create_timer(0.1).timeout
	_find_systems()

func _connect_ui_signals():
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if weapon_list:
		weapon_list.item_selected.connect(_on_weapon_selected)
	if upgrade_button:
		upgrade_button.pressed.connect(_on_upgrade_pressed)
	if dismantle_button:
		dismantle_button.pressed.connect(_on_dismantle_pressed)
	if reroll_button:
		reroll_button.pressed.connect(_on_reroll_pressed)
	if add_augment_button:
		add_augment_button.pressed.connect(_on_add_augment_pressed)

func _find_systems():
	# Find RemantlerSystem
	var parent = get_parent()
	while parent and not remantler:
		if parent.has_node("RemantlerSystem"):
			remantler = parent.get_node("RemantlerSystem")
		parent = parent.get_parent()

	if not remantler and has_node("/root/RemantlerSystem"):
		remantler = get_node("/root/RemantlerSystem")

	# Create if needed
	if not remantler:
		remantler = RemantlerSystem.new()
		remantler.name = "RemantlerSystem"
		add_child(remantler)

	# Connect signals
	if remantler:
		if not remantler.weapon_upgraded.is_connected(_on_weapon_upgraded):
			remantler.weapon_upgraded.connect(_on_weapon_upgraded)
		if not remantler.upgrade_failed.is_connected(_on_upgrade_failed):
			remantler.upgrade_failed.connect(_on_upgrade_failed)

	# Find SigilShop
	parent = get_parent()
	while parent and not sigil_shop:
		if parent.has_node("SigilShop"):
			sigil_shop = parent.get_node("SigilShop")
		parent = parent.get_parent()

	if not sigil_shop and has_node("/root/SigilShop"):
		sigil_shop = get_node("/root/SigilShop")

func _input(event):
	if not is_open:
		return

	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()

func open_panel(player_node: Node = null):
	player = player_node
	is_open = true
	visible = true

	# Find player if not provided
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]

	# Update displays
	_update_sigil_display()
	_populate_weapon_list()
	_clear_selection()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_panel():
	is_open = false
	visible = false
	selected_weapon = null

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	panel_closed.emit()

func _update_sigil_display():
	if sigil_label and sigil_shop:
		sigil_label.text = "Sigils: %d" % sigil_shop.get_sigils()

func _populate_weapon_list():
	if not weapon_list or not player:
		return

	weapon_list.clear()

	# Get player's weapons
	if "equipped_weapons" in player:
		for i in range(player.equipped_weapons.size()):
			var weapon = player.equipped_weapons[i]
			if weapon:
				var tier = remantler.get_weapon_tier(weapon) if remantler else 0
				var tier_name = remantler.get_tier_name(tier) if remantler else "Standard"
				var color = remantler.get_tier_color(tier) if remantler else Color.WHITE

				var display_name = "%s (%s)" % [weapon.item_name, tier_name]
				weapon_list.add_item(display_name)
				weapon_list.set_item_custom_fg_color(i, color)
				weapon_list.set_item_metadata(i, weapon)

func _clear_selection():
	selected_weapon = null

	if weapon_stats:
		weapon_stats.text = "[i]Select a weapon to view stats[/i]"
	if upgrade_preview:
		upgrade_preview.text = ""
	if materials_label:
		materials_label.text = ""
	if upgrade_button:
		upgrade_button.disabled = true
	if dismantle_button:
		dismantle_button.disabled = true
	if reroll_button:
		reroll_button.disabled = true

func _on_weapon_selected(index: int):
	if not weapon_list:
		return

	selected_weapon = weapon_list.get_item_metadata(index)
	_update_weapon_display()
	_update_upgrade_display()
	_update_dismantle_display()
	_update_reroll_display()
	_update_augment_display()

func _update_weapon_display():
	if not weapon_stats or not selected_weapon:
		return

	if remantler:
		weapon_stats.text = remantler.get_weapon_stats_display(selected_weapon)
	else:
		weapon_stats.text = selected_weapon.get_tooltip_text() if selected_weapon.has_method("get_tooltip_text") else str(selected_weapon)

func _update_upgrade_display():
	if not selected_weapon or not remantler:
		if upgrade_button:
			upgrade_button.disabled = true
		return

	var sigils = sigil_shop.get_sigils() if sigil_shop else 0
	var current_tier = remantler.get_weapon_tier(selected_weapon)

	# Check if can upgrade
	var can_upgrade = remantler.can_upgrade(selected_weapon, sigils)

	if upgrade_button:
		upgrade_button.disabled = not can_upgrade.can_upgrade
		upgrade_button.text = "UPGRADE" if can_upgrade.can_upgrade else can_upgrade.reason

	# Show cost
	if upgrade_cost_label:
		var cost = remantler.get_upgrade_cost(current_tier)
		if cost > 0:
			upgrade_cost_label.text = "Cost: %d Sigils" % cost
		else:
			upgrade_cost_label.text = "MAX TIER"

	# Show materials needed
	if materials_label:
		var materials = remantler.get_material_cost(current_tier)
		if materials.size() > 0:
			var mat_text = "[color=yellow]Materials Required:[/color]\n"
			for mat in materials:
				var have = _get_player_material_count(mat)
				var need = materials[mat]
				var color = "lime" if have >= need else "red"
				mat_text += "  %s: [color=%s]%d/%d[/color]\n" % [_format_material_name(mat), color, have, need]
			materials_label.text = mat_text
		else:
			materials_label.text = ""

	# Show preview
	if upgrade_preview and current_tier < 6:
		var preview = remantler.get_upgrade_preview(selected_weapon)
		var preview_text = "[color=cyan]After Upgrade:[/color]\n"
		preview_text += "  Tier: [color=%s]%s[/color]\n" % [remantler.get_tier_color(preview.upgraded.tier).to_html(), preview.upgraded.tier_name]
		preview_text += "  Damage: %.1f [color=lime](+%.1f)[/color]\n" % [preview.upgraded.damage, preview.changes.damage]
		if preview.changes.crit_chance > 0:
			preview_text += "  Crit: +%.1f%%\n" % (preview.changes.crit_chance * 100)
		if preview.changes.sockets > 0:
			preview_text += "  Sockets: +%d\n" % preview.changes.sockets
		upgrade_preview.text = preview_text
	elif upgrade_preview:
		upgrade_preview.text = "[color=gold]Maximum tier reached![/color]"

func _update_dismantle_display():
	if not selected_weapon or not remantler:
		if dismantle_button:
			dismantle_button.disabled = true
		return

	if dismantle_button:
		dismantle_button.disabled = false

	if dismantle_preview:
		var returns = remantler.get_dismantle_returns(selected_weapon)
		var preview_text = "Returns: %d Sigils" % returns.sigils
		if returns.materials.size() > 0:
			preview_text += "\nMaterials: "
			for mat in returns.materials:
				preview_text += "%s x%d, " % [_format_material_name(mat), returns.materials[mat]]
			preview_text = preview_text.trim_suffix(", ")
		dismantle_preview.text = preview_text

func _update_reroll_display():
	if not selected_weapon or not remantler:
		if reroll_button:
			reroll_button.disabled = true
		return

	var sigils = sigil_shop.get_sigils() if sigil_shop else 0
	var can_reroll = remantler.can_reroll(selected_weapon, sigils)

	if reroll_button:
		reroll_button.disabled = not can_reroll

	if reroll_cost_label:
		reroll_cost_label.text = "Cost: %d Sigils" % RemantlerSystem.REROLL_COST

func _update_augment_display():
	if not augment_list or not selected_weapon:
		return

	augment_list.clear()

	# Show current augments
	var current_sockets = selected_weapon.socket_count if "socket_count" in selected_weapon else 0
	var max_sockets = selected_weapon.max_sockets if "max_sockets" in selected_weapon else 0

	# Get augments
	var augments = []
	if "augments" in selected_weapon:
		augments = selected_weapon.augments
	elif selected_weapon.has_meta("augments"):
		augments = selected_weapon.get_meta("augments")

	for i in range(max_sockets):
		if i < augments.size():
			var aug = augments[i]
			augment_list.add_item("[%d] %s" % [i + 1, aug.item_name])
			augment_list.set_item_custom_fg_color(i, Color(0.7, 0.3, 1.0))
		else:
			augment_list.add_item("[%d] Empty Socket" % (i + 1))
			augment_list.set_item_custom_fg_color(i, Color(0.5, 0.5, 0.5))

	if add_augment_button:
		add_augment_button.disabled = current_sockets >= max_sockets

func _get_player_material_count(material_id: String) -> int:
	if has_node("/root/PlayerPersistence"):
		var persistence = get_node("/root/PlayerPersistence")
		if persistence.player_data.has("materials"):
			return persistence.player_data.materials.get(material_id, 0)
	return 0

func _format_material_name(material_id: String) -> String:
	match material_id:
		"scrap_small": return "Small Scrap"
		"scrap_medium": return "Medium Scrap"
		"scrap_large": return "Large Scrap"
		"weapon_parts": return "Weapon Parts"
		"rare_alloy": return "Rare Alloy"
		"mythic_core": return "Mythic Core"
	return material_id.capitalize().replace("_", " ")

# ============================================
# BUTTON HANDLERS
# ============================================

func _on_upgrade_pressed():
	if not selected_weapon or not remantler:
		return

	if remantler.upgrade_weapon(selected_weapon, sigil_shop):
		_update_weapon_display()
		_update_upgrade_display()
		_populate_weapon_list()  # Refresh list to show new tier
		_update_sigil_display()

func _on_weapon_upgraded(weapon: Resource, new_tier: int):
	_show_notification("Weapon upgraded to %s tier!" % remantler.get_tier_name(new_tier), Color(0.2, 1.0, 0.4))
	weapon_upgraded.emit(weapon)

func _on_upgrade_failed(reason: String):
	_show_notification("Upgrade failed: %s" % reason, Color(1.0, 0.3, 0.3))

func _on_dismantle_pressed():
	if not selected_weapon or not remantler:
		return

	# Confirm dialog would be nice here
	var returns = remantler.dismantle_weapon(selected_weapon, sigil_shop)

	_show_notification("Dismantled for %d sigils!" % returns.sigils, Color(0.8, 0.6, 0.2))

	# Remove weapon from player
	if player and "equipped_weapons" in player:
		var index = player.equipped_weapons.find(selected_weapon)
		if index >= 0:
			player.equipped_weapons.remove_at(index)

	_populate_weapon_list()
	_clear_selection()
	_update_sigil_display()

func _on_reroll_pressed():
	if not selected_weapon or not remantler:
		return

	if remantler.reroll_weapon_ability(selected_weapon, sigil_shop):
		_update_weapon_display()
		_update_sigil_display()
		_show_notification("Ability rerolled!", Color(0.7, 0.3, 1.0))
	else:
		_show_notification("Reroll failed!", Color(1.0, 0.3, 0.3))

func _on_add_augment_pressed():
	# Would open augment selection dialog
	_show_notification("Augment system coming soon!", Color(0.7, 0.7, 0.7))

func _on_close_pressed():
	close_panel()

func _show_notification(message: String, color: Color):
	var notification = Label.new()
	notification.text = message
	notification.add_theme_color_override("font_color", color)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.position = Vector2(size.x / 2 - 150, size.y - 80)
	add_child(notification)

	var tween = create_tween()
	tween.tween_property(notification, "modulate:a", 0.0, 1.5)
	tween.tween_callback(notification.queue_free)

# ============================================
# STATIC SCENE BUILDER
# ============================================

static func create_panel_scene() -> Control:
	"""Creates the remantler panel UI scene structure programmatically"""
	var root = RemantlerPanel.new()
	root.name = "RemantlerPanel"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Main panel
	var panel = PanelContainer.new()
	panel.name = "PanelContainer"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1000, 650)
	panel.offset_left = -500
	panel.offset_right = 500
	panel.offset_top = -325
	panel.offset_bottom = 325
	root.add_child(panel)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.6, 0.3, 0.8)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Header
	var header = HBoxContainer.new()
	header.name = "Header"
	vbox.add_child(header)

	var title = Label.new()
	title.text = "REMANTLER - Weapon Upgrade Station"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.7, 0.4, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var sigil_label = Label.new()
	sigil_label.name = "SigilLabel"
	sigil_label.text = "Sigils: 0"
	sigil_label.add_theme_font_size_override("font_size", 18)
	sigil_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8))
	header.add_child(sigil_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	header.add_child(spacer)

	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(40, 40)
	header.add_child(close_btn)

	# Content HBox
	var content = HBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 15)
	vbox.add_child(content)

	# Left panel - Weapon list
	var left_panel = VBoxContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.custom_minimum_size = Vector2(250, 0)
	content.add_child(left_panel)

	var weapons_title = Label.new()
	weapons_title.text = "Your Weapons"
	weapons_title.add_theme_font_size_override("font_size", 16)
	left_panel.add_child(weapons_title)

	var weapon_list = ItemList.new()
	weapon_list.name = "WeaponList"
	weapon_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(weapon_list)

	# Center panel - Stats and upgrade
	var center_panel = VBoxContainer.new()
	center_panel.name = "CenterPanel"
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.add_theme_constant_override("separation", 10)
	content.add_child(center_panel)

	var weapon_stats = RichTextLabel.new()
	weapon_stats.name = "WeaponStats"
	weapon_stats.bbcode_enabled = true
	weapon_stats.custom_minimum_size = Vector2(0, 200)
	weapon_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_panel.add_child(weapon_stats)

	# Upgrade section
	var upgrade_section = VBoxContainer.new()
	upgrade_section.name = "UpgradeSection"
	center_panel.add_child(upgrade_section)

	var upgrade_title = Label.new()
	upgrade_title.text = "UPGRADE"
	upgrade_title.add_theme_font_size_override("font_size", 14)
	upgrade_title.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	upgrade_section.add_child(upgrade_title)

	var materials_label = RichTextLabel.new()
	materials_label.name = "MaterialsLabel"
	materials_label.bbcode_enabled = true
	materials_label.custom_minimum_size = Vector2(0, 80)
	upgrade_section.add_child(materials_label)

	var preview_label = RichTextLabel.new()
	preview_label.name = "PreviewLabel"
	preview_label.bbcode_enabled = true
	preview_label.custom_minimum_size = Vector2(0, 80)
	upgrade_section.add_child(preview_label)

	var cost_label = Label.new()
	cost_label.name = "CostLabel"
	cost_label.text = "Cost: 0 Sigils"
	upgrade_section.add_child(cost_label)

	var upgrade_btn = Button.new()
	upgrade_btn.name = "UpgradeButton"
	upgrade_btn.text = "UPGRADE WEAPON"
	upgrade_btn.disabled = true
	upgrade_section.add_child(upgrade_btn)

	# Dismantle section
	var dismantle_section = HBoxContainer.new()
	dismantle_section.name = "DismantleSection"
	center_panel.add_child(dismantle_section)

	var dismantle_btn = Button.new()
	dismantle_btn.name = "DismantleButton"
	dismantle_btn.text = "DISMANTLE"
	dismantle_btn.disabled = true
	dismantle_section.add_child(dismantle_btn)

	var dismantle_preview = Label.new()
	dismantle_preview.name = "PreviewLabel"
	dismantle_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dismantle_section.add_child(dismantle_preview)

	# Reroll section
	var reroll_section = HBoxContainer.new()
	reroll_section.name = "RerollSection"
	center_panel.add_child(reroll_section)

	var reroll_btn = Button.new()
	reroll_btn.name = "RerollButton"
	reroll_btn.text = "REROLL ABILITY"
	reroll_btn.disabled = true
	reroll_section.add_child(reroll_btn)

	var reroll_cost = Label.new()
	reroll_cost.name = "CostLabel"
	reroll_cost.text = "Cost: 250 Sigils"
	reroll_section.add_child(reroll_cost)

	# Right panel - Augments
	var right_panel = VBoxContainer.new()
	right_panel.name = "RightPanel"
	right_panel.custom_minimum_size = Vector2(200, 0)
	content.add_child(right_panel)

	var augment_title = Label.new()
	augment_title.text = "Augment Sockets"
	augment_title.add_theme_font_size_override("font_size", 16)
	right_panel.add_child(augment_title)

	var augment_list = ItemList.new()
	augment_list.name = "AugmentList"
	augment_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(augment_list)

	var add_augment_btn = Button.new()
	add_augment_btn.name = "AddAugmentButton"
	add_augment_btn.text = "ADD AUGMENT"
	add_augment_btn.disabled = true
	right_panel.add_child(add_augment_btn)

	return root
