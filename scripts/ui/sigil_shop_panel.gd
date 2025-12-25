extends Control
class_name SigilShopPanel

# Sigil Shop UI Panel
# Displays shop items organized by category with purchase functionality

signal shop_closed
signal item_selected(item_id: String)
signal item_purchased(item_id: String)

# References
var sigil_shop: SigilShop = null
var player: Node = null

# UI State
var current_category: int = 0  # SigilShop.ShopCategory
var selected_item_id: String = ""
var is_open: bool = false

# UI Elements (assigned in _ready or via export)
@onready var panel_container: PanelContainer = $PanelContainer
@onready var category_tabs: TabBar = $PanelContainer/VBox/CategoryTabs
@onready var item_grid: GridContainer = $PanelContainer/VBox/ScrollContainer/ItemGrid
@onready var sigil_label: Label = $PanelContainer/VBox/Header/SigilLabel
@onready var tooltip_panel: PanelContainer = $TooltipPanel
@onready var tooltip_label: RichTextLabel = $TooltipPanel/TooltipLabel
@onready var close_button: Button = $PanelContainer/VBox/Header/CloseButton

# Item button scene (created dynamically)
var item_button_template: PackedScene = null

func _ready():
	# Hide by default
	visible = false
	if tooltip_panel:
		tooltip_panel.visible = false

	# Setup category tabs
	_setup_category_tabs()

	# Connect signals
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if category_tabs:
		category_tabs.tab_changed.connect(_on_category_changed)

	# Find sigil shop
	await get_tree().create_timer(0.1).timeout
	_find_sigil_shop()

func _setup_category_tabs():
	if not category_tabs:
		return

	category_tabs.clear_tabs()
	category_tabs.add_tab("Weapons")
	category_tabs.add_tab("Ammo")
	category_tabs.add_tab("Materials")
	category_tabs.add_tab("Consumables")
	category_tabs.add_tab("Services")

func _find_sigil_shop():
	# Try to find SigilShop in parent or autoload
	var parent = get_parent()
	while parent:
		if parent.has_node("SigilShop"):
			sigil_shop = parent.get_node("SigilShop")
			break
		parent = parent.get_parent()

	if not sigil_shop and has_node("/root/SigilShop"):
		sigil_shop = get_node("/root/SigilShop")

	# Create if not found
	if not sigil_shop:
		sigil_shop = SigilShop.new()
		sigil_shop.name = "SigilShop"
		add_child(sigil_shop)

	# Connect signals
	if sigil_shop:
		if not sigil_shop.sigils_changed.is_connected(_on_sigils_changed):
			sigil_shop.sigils_changed.connect(_on_sigils_changed)
		if not sigil_shop.item_purchased.is_connected(_on_item_purchased):
			sigil_shop.item_purchased.connect(_on_item_purchased)
		if not sigil_shop.purchase_failed.is_connected(_on_purchase_failed):
			sigil_shop.purchase_failed.connect(_on_purchase_failed)

func _input(event):
	if not is_open:
		return

	# Close on escape
	if event.is_action_pressed("ui_cancel"):
		close_shop()
		get_viewport().set_input_as_handled()

func open_shop(player_node: Node = null):
	player = player_node
	is_open = true
	visible = true

	# Find player if not provided
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]

	# Update display
	_update_sigil_display()
	_populate_items()

	# Capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_shop():
	is_open = false
	visible = false
	selected_item_id = ""

	if tooltip_panel:
		tooltip_panel.visible = false

	# Release mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	shop_closed.emit()

func _update_sigil_display():
	if sigil_label and sigil_shop:
		sigil_label.text = "Sigils: %d" % sigil_shop.get_sigils()

func _on_sigils_changed(new_amount: int):
	if sigil_label:
		sigil_label.text = "Sigils: %d" % new_amount

func _on_category_changed(tab_index: int):
	current_category = tab_index
	_populate_items()

func _populate_items():
	if not item_grid or not sigil_shop:
		return

	# Clear existing items
	for child in item_grid.get_children():
		child.queue_free()

	# Get items for current category
	var category = current_category as SigilShop.ShopCategory
	var items = sigil_shop.get_items_by_category(category)

	# Get player level for requirement checking
	var player_level = 1
	if player and "character_attributes" in player and player.character_attributes:
		player_level = player.character_attributes.level

	# Create item buttons
	for shop_item in items:
		var button = _create_item_button(shop_item, player_level)
		item_grid.add_child(button)

func _create_item_button(shop_item, player_level: int) -> Control:
	# Create button container
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(180, 120)

	# Style based on rarity
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_color = shop_item.get_rarity_color()
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	container.add_theme_stylebox_override("panel", style)

	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	container.add_child(vbox)

	# Margin
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	container.add_child(margin)

	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 4)
	margin.add_child(inner_vbox)

	# Item name
	var name_label = Label.new()
	name_label.text = shop_item.name
	name_label.add_theme_color_override("font_color", shop_item.get_rarity_color())
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	inner_vbox.add_child(name_label)

	# Rarity
	var rarity_label = Label.new()
	rarity_label.text = shop_item.get_rarity_name()
	rarity_label.add_theme_font_size_override("font_size", 12)
	rarity_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(rarity_label)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner_vbox.add_child(spacer)

	# Cost
	var cost_label = Label.new()
	var can_afford = sigil_shop.can_afford(shop_item.id)
	var meets_level = player_level >= shop_item.level_requirement
	cost_label.text = "%d Sigils" % shop_item.cost
	cost_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8) if can_afford else Color(1.0, 0.3, 0.3))
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(cost_label)

	# Level requirement if not met
	if not meets_level:
		var level_label = Label.new()
		level_label.text = "Lvl %d Required" % shop_item.level_requirement
		level_label.add_theme_font_size_override("font_size", 11)
		level_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner_vbox.add_child(level_label)

	# Buy button
	var buy_button = Button.new()
	buy_button.text = "BUY"
	buy_button.disabled = not (can_afford and meets_level)
	buy_button.pressed.connect(_on_buy_pressed.bind(shop_item.id))
	inner_vbox.add_child(buy_button)

	# Hover for tooltip
	container.mouse_entered.connect(_on_item_hover.bind(shop_item, container))
	container.mouse_exited.connect(_on_item_unhover)

	return container

func _on_item_hover(shop_item, button_node: Control):
	selected_item_id = shop_item.id

	if tooltip_panel and tooltip_label and sigil_shop:
		var tooltip_text = sigil_shop.get_item_tooltip(shop_item.id)
		tooltip_label.text = tooltip_text
		tooltip_panel.visible = true

		# Position tooltip near the item
		var button_rect = button_node.get_global_rect()
		tooltip_panel.global_position = Vector2(
			button_rect.position.x + button_rect.size.x + 10,
			button_rect.position.y
		)

		# Keep tooltip on screen
		var viewport_size = get_viewport_rect().size
		if tooltip_panel.global_position.x + tooltip_panel.size.x > viewport_size.x:
			tooltip_panel.global_position.x = button_rect.position.x - tooltip_panel.size.x - 10
		if tooltip_panel.global_position.y + tooltip_panel.size.y > viewport_size.y:
			tooltip_panel.global_position.y = viewport_size.y - tooltip_panel.size.y - 10

	item_selected.emit(shop_item.id)

func _on_item_unhover():
	if tooltip_panel:
		tooltip_panel.visible = false

func _on_buy_pressed(item_id: String):
	if sigil_shop:
		if sigil_shop.purchase_item(item_id, player):
			# Refresh display
			_update_sigil_display()
			_populate_items()

func _on_item_purchased(item_name: String, cost: int):
	# Show purchase notification
	_show_notification("Purchased %s for %d sigils!" % [item_name, cost], Color(0.2, 1.0, 0.4))
	item_purchased.emit(selected_item_id)

func _on_purchase_failed(reason: String):
	_show_notification("Purchase failed: %s" % reason, Color(1.0, 0.3, 0.3))

func _show_notification(message: String, color: Color):
	# Create floating notification
	var notification = Label.new()
	notification.text = message
	notification.add_theme_color_override("font_color", color)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.position = Vector2(size.x / 2 - 150, size.y - 80)
	add_child(notification)

	# Animate and remove
	var tween = create_tween()
	tween.tween_property(notification, "modulate:a", 0.0, 1.5)
	tween.tween_callback(notification.queue_free)

func _on_close_pressed():
	close_shop()

# ============================================
# STATIC SCENE BUILDER
# ============================================

static func create_shop_scene() -> Control:
	"""Creates the shop UI scene structure programmatically"""
	var root = SigilShopPanel.new()
	root.name = "SigilShopPanel"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Main panel
	var panel = PanelContainer.new()
	panel.name = "PanelContainer"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(900, 600)
	panel.offset_left = -450
	panel.offset_right = 450
	panel.offset_top = -300
	panel.offset_bottom = 300
	root.add_child(panel)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.3, 0.5, 0.8)
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
	title.text = "SIGIL SHOP"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
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

	# Category tabs
	var tabs = TabBar.new()
	tabs.name = "CategoryTabs"
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	vbox.add_child(tabs)

	# Scroll container
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	# Item grid
	var grid = GridContainer.new()
	grid.name = "ItemGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	# Tooltip panel
	var tooltip = PanelContainer.new()
	tooltip.name = "TooltipPanel"
	tooltip.visible = false
	tooltip.custom_minimum_size = Vector2(300, 200)
	tooltip.z_index = 100
	root.add_child(tooltip)

	var tooltip_style = StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	tooltip_style.set_border_width_all(1)
	tooltip_style.border_color = Color(0.4, 0.4, 0.5)
	tooltip_style.set_corner_radius_all(4)
	tooltip.add_theme_stylebox_override("panel", tooltip_style)

	var tooltip_margin = MarginContainer.new()
	tooltip_margin.add_theme_constant_override("margin_left", 10)
	tooltip_margin.add_theme_constant_override("margin_right", 10)
	tooltip_margin.add_theme_constant_override("margin_top", 10)
	tooltip_margin.add_theme_constant_override("margin_bottom", 10)
	tooltip.add_child(tooltip_margin)

	var tooltip_label = RichTextLabel.new()
	tooltip_label.name = "TooltipLabel"
	tooltip_label.bbcode_enabled = true
	tooltip_label.fit_content = true
	tooltip_margin.add_child(tooltip_label)

	return root
