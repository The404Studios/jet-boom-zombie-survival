extends Control
class_name LoginPanel

# Login and registration UI panel
# Integrates with the Backend autoload for authentication

signal login_successful(player_data: Dictionary)
signal panel_closed

# UI References
var login_container: VBoxContainer
var register_container: VBoxContainer

# Login fields
var login_username: LineEdit
var login_password: LineEdit
var login_button: Button
var login_error_label: Label
var switch_to_register_button: Button

# Register fields
var register_username: LineEdit
var register_email: LineEdit
var register_password: LineEdit
var register_password_confirm: LineEdit
var register_button: Button
var register_error_label: Label
var switch_to_login_button: Button

# State
var is_loading: bool = false
var backend: Node = null

func _ready():
	backend = get_node_or_null("/root/Backend")
	_create_ui()
	_connect_backend_signals()

	# Show login by default
	_show_login_form()

func _create_ui():
	# Main background
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Main panel
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(450, 500)
	center.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_top = 2
	style.border_color = Color(1, 0.8, 0.3, 0.5)
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20)
	margin.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.name = "Title"
	title.text = "ZOMBIE SURVIVAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	main_vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "Sign In"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	main_vbox.add_child(subtitle)

	# Login container
	login_container = VBoxContainer.new()
	login_container.name = "LoginContainer"
	login_container.add_theme_constant_override("separation", 15)
	main_vbox.add_child(login_container)
	_create_login_form(login_container)

	# Register container
	register_container = VBoxContainer.new()
	register_container.name = "RegisterContainer"
	register_container.add_theme_constant_override("separation", 15)
	register_container.visible = false
	main_vbox.add_child(register_container)
	_create_register_form(register_container)

	# Close button
	var close_hbox = HBoxContainer.new()
	close_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(close_hbox)

	var close_btn = Button.new()
	close_btn.text = "BACK TO MENU"
	close_btn.custom_minimum_size = Vector2(150, 35)
	close_btn.pressed.connect(_on_close_pressed)
	close_hbox.add_child(close_btn)

func _create_login_form(parent: VBoxContainer):
	# Username
	var username_label = Label.new()
	username_label.text = "Username"
	username_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(username_label)

	login_username = LineEdit.new()
	login_username.placeholder_text = "Enter username..."
	login_username.custom_minimum_size = Vector2(0, 40)
	parent.add_child(login_username)

	# Password
	var password_label = Label.new()
	password_label.text = "Password"
	password_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(password_label)

	login_password = LineEdit.new()
	login_password.placeholder_text = "Enter password..."
	login_password.secret = true
	login_password.custom_minimum_size = Vector2(0, 40)
	login_password.text_submitted.connect(func(_t): _on_login_pressed())
	parent.add_child(login_password)

	# Error label
	login_error_label = Label.new()
	login_error_label.name = "ErrorLabel"
	login_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	login_error_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	login_error_label.add_theme_font_size_override("font_size", 12)
	login_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	login_error_label.visible = false
	parent.add_child(login_error_label)

	# Login button
	login_button = Button.new()
	login_button.text = "SIGN IN"
	login_button.custom_minimum_size = Vector2(0, 45)
	login_button.pressed.connect(_on_login_pressed)
	parent.add_child(login_button)

	# Style login button
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.3, 0.6, 0.3)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	login_button.add_theme_stylebox_override("normal", btn_style)

	# Switch to register
	var switch_hbox = HBoxContainer.new()
	switch_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	switch_hbox.add_theme_constant_override("separation", 5)
	parent.add_child(switch_hbox)

	var switch_label = Label.new()
	switch_label.text = "Don't have an account?"
	switch_label.add_theme_font_size_override("font_size", 12)
	switch_hbox.add_child(switch_label)

	switch_to_register_button = Button.new()
	switch_to_register_button.text = "Register"
	switch_to_register_button.flat = true
	switch_to_register_button.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	switch_to_register_button.add_theme_font_size_override("font_size", 12)
	switch_to_register_button.pressed.connect(_show_register_form)
	switch_hbox.add_child(switch_to_register_button)

func _create_register_form(parent: VBoxContainer):
	# Username
	var username_label = Label.new()
	username_label.text = "Username"
	username_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(username_label)

	register_username = LineEdit.new()
	register_username.placeholder_text = "Choose a username..."
	register_username.custom_minimum_size = Vector2(0, 40)
	parent.add_child(register_username)

	# Email
	var email_label = Label.new()
	email_label.text = "Email"
	email_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(email_label)

	register_email = LineEdit.new()
	register_email.placeholder_text = "Enter email address..."
	register_email.custom_minimum_size = Vector2(0, 40)
	parent.add_child(register_email)

	# Password
	var password_label = Label.new()
	password_label.text = "Password"
	password_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(password_label)

	register_password = LineEdit.new()
	register_password.placeholder_text = "Choose a password..."
	register_password.secret = true
	register_password.custom_minimum_size = Vector2(0, 40)
	parent.add_child(register_password)

	# Confirm password
	var confirm_label = Label.new()
	confirm_label.text = "Confirm Password"
	confirm_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(confirm_label)

	register_password_confirm = LineEdit.new()
	register_password_confirm.placeholder_text = "Confirm password..."
	register_password_confirm.secret = true
	register_password_confirm.custom_minimum_size = Vector2(0, 40)
	register_password_confirm.text_submitted.connect(func(_t): _on_register_pressed())
	parent.add_child(register_password_confirm)

	# Error label
	register_error_label = Label.new()
	register_error_label.name = "ErrorLabel"
	register_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	register_error_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	register_error_label.add_theme_font_size_override("font_size", 12)
	register_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	register_error_label.visible = false
	parent.add_child(register_error_label)

	# Register button
	register_button = Button.new()
	register_button.text = "CREATE ACCOUNT"
	register_button.custom_minimum_size = Vector2(0, 45)
	register_button.pressed.connect(_on_register_pressed)
	parent.add_child(register_button)

	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.3, 0.5, 0.7)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	register_button.add_theme_stylebox_override("normal", btn_style)

	# Switch to login
	var switch_hbox = HBoxContainer.new()
	switch_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	switch_hbox.add_theme_constant_override("separation", 5)
	parent.add_child(switch_hbox)

	var switch_label = Label.new()
	switch_label.text = "Already have an account?"
	switch_label.add_theme_font_size_override("font_size", 12)
	switch_hbox.add_child(switch_label)

	switch_to_login_button = Button.new()
	switch_to_login_button.text = "Sign In"
	switch_to_login_button.flat = true
	switch_to_login_button.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	switch_to_login_button.add_theme_font_size_override("font_size", 12)
	switch_to_login_button.pressed.connect(_show_login_form)
	switch_hbox.add_child(switch_to_login_button)

func _connect_backend_signals():
	if backend:
		backend.logged_in.connect(_on_logged_in)
		backend.login_failed.connect(_on_login_failed)

func _show_login_form():
	login_container.visible = true
	register_container.visible = false
	login_error_label.visible = false

	var subtitle = get_node_or_null("CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Subtitle")
	if subtitle:
		subtitle.text = "Sign In"

func _show_register_form():
	login_container.visible = false
	register_container.visible = true
	register_error_label.visible = false

	var subtitle = get_node_or_null("CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Subtitle")
	if subtitle:
		subtitle.text = "Create Account"

func _on_login_pressed():
	if is_loading:
		return

	var username = login_username.text.strip_edges()
	var password = login_password.text

	# Validate
	if username.length() < 3:
		_show_login_error("Username must be at least 3 characters")
		return

	if password.length() < 6:
		_show_login_error("Password must be at least 6 characters")
		return

	# Start login
	is_loading = true
	login_button.text = "SIGNING IN..."
	login_button.disabled = true
	login_error_label.visible = false

	if backend:
		backend.login(username, password)
	else:
		# No backend - simulate success for testing
		await get_tree().create_timer(0.5).timeout
		_on_logged_in({"username": username, "level": 1})

func _on_register_pressed():
	if is_loading:
		return

	var username = register_username.text.strip_edges()
	var email = register_email.text.strip_edges()
	var password = register_password.text
	var password_confirm = register_password_confirm.text

	# Validate
	if username.length() < 3:
		_show_register_error("Username must be at least 3 characters")
		return

	if not email.contains("@"):
		_show_register_error("Please enter a valid email address")
		return

	if password.length() < 6:
		_show_register_error("Password must be at least 6 characters")
		return

	if password != password_confirm:
		_show_register_error("Passwords do not match")
		return

	# Start registration
	is_loading = true
	register_button.text = "CREATING ACCOUNT..."
	register_button.disabled = true
	register_error_label.visible = false

	if backend:
		backend.register(username, email, password)
	else:
		# No backend - simulate success
		await get_tree().create_timer(0.5).timeout
		_on_logged_in({"username": username, "level": 1})

func _on_logged_in(player_data: Dictionary):
	is_loading = false
	login_successful.emit(player_data)

func _on_login_failed(error: String):
	is_loading = false

	if login_container.visible:
		login_button.text = "SIGN IN"
		login_button.disabled = false
		_show_login_error(error)
	else:
		register_button.text = "CREATE ACCOUNT"
		register_button.disabled = false
		_show_register_error(error)

func _show_login_error(error: String):
	login_error_label.text = error
	login_error_label.visible = true

func _show_register_error(error: String):
	register_error_label.text = error
	register_error_label.visible = true

func _on_close_pressed():
	panel_closed.emit()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		panel_closed.emit()
		get_viewport().set_input_as_handled()
