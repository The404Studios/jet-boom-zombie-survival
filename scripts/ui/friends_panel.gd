extends Control
class_name FriendsPanel

signal friend_invited(friend_id: int)
signal friend_removed(friend_id: int)
signal panel_closed

# UI Elements
var friends_list: VBoxContainer
var pending_list: VBoxContainer
var search_input: LineEdit
var add_friend_button: Button
var close_button: Button
var tabs: TabContainer

# Data
var friends: Array = []
var pending_requests: Array = []

# Backend integration
var backend: Node = null

func _ready():
	backend = get_node_or_null("/root/Backend")
	_create_ui()
	_connect_signals()
	_load_friends()

func _create_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 50)
	add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_vbox)

	# Header
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(header_hbox)

	var title = Label.new()
	title.text = "FRIENDS"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	header_hbox.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	close_button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(40, 40)
	header_hbox.add_child(close_button)

	# Add friend section
	var add_section = HBoxContainer.new()
	add_section.add_theme_constant_override("separation", 10)
	main_vbox.add_child(add_section)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Enter username to add..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_section.add_child(search_input)

	add_friend_button = Button.new()
	add_friend_button.text = "ADD FRIEND"
	add_friend_button.custom_minimum_size = Vector2(120, 35)
	add_section.add_child(add_friend_button)

	# Tabs for friends and pending requests
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tabs)

	# Friends tab
	var friends_scroll = ScrollContainer.new()
	friends_scroll.name = "Friends"
	friends_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(friends_scroll)

	friends_list = VBoxContainer.new()
	friends_list.add_theme_constant_override("separation", 5)
	friends_scroll.add_child(friends_list)

	# Pending requests tab
	var pending_scroll = ScrollContainer.new()
	pending_scroll.name = "Pending"
	pending_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(pending_scroll)

	pending_list = VBoxContainer.new()
	pending_list.add_theme_constant_override("separation", 5)
	pending_scroll.add_child(pending_list)

func _connect_signals():
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if add_friend_button:
		add_friend_button.pressed.connect(_on_add_friend_pressed)
	if search_input:
		search_input.text_submitted.connect(func(_text): _on_add_friend_pressed())

func _load_friends():
	if not backend or not backend.is_authenticated:
		_show_login_required()
		return

	backend.get_friends(func(response):
		if response.success and response.has("friends"):
			friends = response.friends
			_display_friends()
	)

	backend.get_pending_friend_requests(func(response):
		if response.success and response.has("requests"):
			pending_requests = response.requests
			_display_pending_requests()
	)

func _show_login_required():
	# Clear lists
	for child in friends_list.get_children():
		child.queue_free()

	var label = Label.new()
	label.text = "Login required to view friends"
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	friends_list.add_child(label)

func _display_friends():
	# Clear existing
	for child in friends_list.get_children():
		child.queue_free()

	if friends.is_empty():
		var label = Label.new()
		label.text = "No friends yet. Add some!"
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		friends_list.add_child(label)
		return

	for friend in friends:
		var entry = _create_friend_entry(friend)
		friends_list.add_child(entry)

func _create_friend_entry(friend: Dictionary) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 50)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	margin.add_child(hbox)

	# Online status indicator
	var status_indicator = ColorRect.new()
	status_indicator.custom_minimum_size = Vector2(10, 10)
	var is_online = friend.get("isOnline", false)
	status_indicator.color = Color.GREEN if is_online else Color.GRAY
	hbox.add_child(status_indicator)

	# Name and status
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label = Label.new()
	name_label.text = friend.get("username", "Unknown")
	name_label.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(name_label)

	var status_label = Label.new()
	var status_text = "Online" if is_online else "Offline"
	if is_online and friend.has("currentGame"):
		status_text = "In Game"
	status_label.text = status_text
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	info_vbox.add_child(status_label)

	# Invite button
	if is_online:
		var invite_btn = Button.new()
		invite_btn.text = "INVITE"
		invite_btn.custom_minimum_size = Vector2(70, 30)
		invite_btn.pressed.connect(_on_invite_friend.bind(friend.get("id", 0)))
		hbox.add_child(invite_btn)

	# Remove button
	var remove_btn = Button.new()
	remove_btn.text = "X"
	remove_btn.custom_minimum_size = Vector2(30, 30)
	remove_btn.pressed.connect(_on_remove_friend.bind(friend.get("id", 0)))
	hbox.add_child(remove_btn)

	return panel

func _display_pending_requests():
	# Clear existing
	for child in pending_list.get_children():
		child.queue_free()

	if pending_requests.is_empty():
		var label = Label.new()
		label.text = "No pending friend requests"
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		pending_list.add_child(label)
		return

	for request in pending_requests:
		var entry = _create_pending_entry(request)
		pending_list.add_child(entry)

func _create_pending_entry(request: Dictionary) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 50)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	margin.add_child(hbox)

	# Name
	var name_label = Label.new()
	name_label.text = request.get("fromUsername", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(name_label)

	# Accept button
	var accept_btn = Button.new()
	accept_btn.text = "ACCEPT"
	accept_btn.custom_minimum_size = Vector2(80, 30)
	accept_btn.pressed.connect(_on_accept_request.bind(request.get("id", 0)))
	hbox.add_child(accept_btn)

	# Decline button
	var decline_btn = Button.new()
	decline_btn.text = "DECLINE"
	decline_btn.custom_minimum_size = Vector2(80, 30)
	decline_btn.pressed.connect(_on_decline_request.bind(request.get("id", 0)))
	hbox.add_child(decline_btn)

	return panel

func _on_add_friend_pressed():
	var username = search_input.text.strip_edges()
	if username.is_empty():
		return

	if not backend or not backend.is_authenticated:
		return

	backend.send_friend_request(username, func(response):
		if response.success:
			search_input.text = ""
			_show_message("Friend Request Sent", "Request sent to %s" % username)
		else:
			_show_message("Error", response.get("error", "Failed to send request"))
	)

func _on_invite_friend(friend_id: int):
	friend_invited.emit(friend_id)

	# Send game invite through WebSocket
	var websocket = get_node_or_null("/root/WebSocketHub")
	if websocket and websocket.is_connected:
		websocket.send_game_invite(friend_id)
		_show_message("Invite Sent", "Game invite sent!")

func _on_remove_friend(friend_id: int):
	if not backend:
		return

	backend.remove_friend(friend_id, func(response):
		if response.success:
			friend_removed.emit(friend_id)
			_load_friends()  # Refresh list
		else:
			_show_message("Error", response.get("error", "Failed to remove friend"))
	)

func _on_accept_request(request_id: int):
	if not backend:
		return

	backend.accept_friend_request(request_id, func(response):
		if response.success:
			_load_friends()  # Refresh both lists
		else:
			_show_message("Error", response.get("error", "Failed to accept request"))
	)

func _on_decline_request(request_id: int):
	if not backend:
		return

	backend.decline_friend_request(request_id, func(response):
		if response.success:
			_load_friends()  # Refresh list
		else:
			_show_message("Error", response.get("error", "Failed to decline request"))
	)

func _on_close_pressed():
	panel_closed.emit()
	visible = false

func _show_message(title: String, message: String):
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()

func open():
	visible = true
	_load_friends()

func close():
	visible = false

func _exit_tree():
	# Clear data arrays
	friends.clear()
	pending_requests.clear()
