extends Control
class_name TeleportUI

# UI for selecting teleport destinations between linked sigils

signal destination_selected(sigil: CaptureSigil)
signal cancelled

var source_sigil: CaptureSigil
var destinations: Array = []
var current_player: Node
var selected_index: int = 0

var panel: Panel
var title_label: Label
var destination_container: VBoxContainer
var destination_buttons: Array = []

const BUTTON_STYLE_NORMAL = Color(0.2, 0.3, 0.5)
const BUTTON_STYLE_HOVER = Color(0.3, 0.5, 0.7)
const BUTTON_STYLE_SELECTED = Color(0.4, 0.6, 1.0)

func _ready():
	add_to_group("teleport_ui")
	visible = false
	_create_ui()

func _create_ui():
	# Main panel
	panel = Panel.new()
	panel.name = "TeleportPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 300)
	panel.position = Vector2(-200, -150)
	add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.18, 0.95)
	style.border_color = Color(0.4, 0.6, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_child(margin)

	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(inner_vbox)

	# Title
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "SELECT DESTINATION"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	inner_vbox.add_child(title_label)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	inner_vbox.add_child(sep)

	# Destinations container
	destination_container = VBoxContainer.new()
	destination_container.name = "DestinationContainer"
	destination_container.add_theme_constant_override("separation", 8)
	inner_vbox.add_child(destination_container)

	# Cancel button
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel [ESC]"
	cancel_btn.pressed.connect(_on_cancel_pressed)
	inner_vbox.add_child(cancel_btn)

func _input(event):
	if not visible:
		return

	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_select_previous()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_select_next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_confirm_selection()
		get_viewport().set_input_as_handled()

func show_destinations(source: CaptureSigil, dest_list: Array, player: Node):
	source_sigil = source
	destinations = dest_list
	current_player = player
	selected_index = 0

	_populate_destinations()

	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _populate_destinations():
	# Clear existing
	for btn in destination_buttons:
		btn.queue_free()
	destination_buttons.clear()

	# Create buttons for each destination
	for i in range(destinations.size()):
		var sigil = destinations[i] as CaptureSigil
		var btn = _create_destination_button(sigil, i)
		destination_container.add_child(btn)
		destination_buttons.append(btn)

	_update_selection()

func _create_destination_button(sigil: CaptureSigil, index: int) -> Button:
	var btn = Button.new()
	btn.name = "Dest_%d" % index
	btn.custom_minimum_size = Vector2(350, 50)

	# Calculate distance from source
	var distance = source_sigil.global_position.distance_to(sigil.global_position)

	btn.text = "%s  (%.0fm)" % [sigil.sigil_name, distance]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Style
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = BUTTON_STYLE_NORMAL
	normal_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = BUTTON_STYLE_HOVER
	hover_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = BUTTON_STYLE_SELECTED
	pressed_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.pressed.connect(_on_destination_pressed.bind(index))

	return btn

func _update_selection():
	for i in range(destination_buttons.size()):
		var btn = destination_buttons[i]
		var style = btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		if i == selected_index:
			style.bg_color = BUTTON_STYLE_SELECTED
			style.border_color = Color.WHITE
			style.set_border_width_all(2)
		else:
			style.bg_color = BUTTON_STYLE_NORMAL
			style.set_border_width_all(0)
		btn.add_theme_stylebox_override("normal", style)

func _select_previous():
	selected_index = (selected_index - 1 + destinations.size()) % destinations.size()
	_update_selection()

func _select_next():
	selected_index = (selected_index + 1) % destinations.size()
	_update_selection()

func _confirm_selection():
	if selected_index >= 0 and selected_index < destinations.size():
		var dest = destinations[selected_index]
		_teleport_to(dest)

func _on_destination_pressed(index: int):
	selected_index = index
	_confirm_selection()

func _teleport_to(destination: CaptureSigil):
	if source_sigil and current_player:
		source_sigil.teleport_to(current_player, destination)
		destination_selected.emit(destination)

	_close()

func _on_cancel_pressed():
	cancelled.emit()
	_close()

func _close():
	visible = false
	source_sigil = null
	destinations.clear()
	current_player = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
